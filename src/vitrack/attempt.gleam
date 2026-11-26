import gleam/bit_array
import gleam/bool
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pog.{type Connection}
import vitrack/github
import vitrack/typs/attempt_types.{
  type Attempt, type Commit, type Entry, Attempt, Commit, Entry,
}
import vitrack/typs/github_types.{type App}

pub const kinds = ["emulator", "recompiler", "compatibility layer", "other"]

pub const gpus = ["unknown", "amd", "nvidia", "both"]

pub const statuses = [
  "nothing",
  "boots",
  "menus",
  "in-game",
  "playable",
  "abandoned",
]

const columns =
  "id, slug, name, kind, description, owner, status, repo,
  discord, mirrors, coalesce(extract(epoch from now() - pushed_at)::int, -1),
  repo <> '' and checked_at < now() - interval '5 minutes',
  stars, forks, issues, language, (
    select count(*) from commits
    where attempt_id = attempts.id
      and committed_at > now() - interval '7 days'
  ), gpu"

pub fn all(db: Connection) -> List(Attempt) {
  let assert Ok(found) =
    pog.query("select " <> columns <> " from attempts order by lower(name)")
    |> pog.returning(decoder())
    |> pog.execute(db)
  list.sort(found.rows, fn(one, other) { int.compare(score(other), score(one)) })
}

pub fn stage(status: String) -> Int {
  case status {
    "playable" -> 5
    "in-game" -> 4
    "menus" -> 3
    "boots" -> 2
    "nothing" -> 1
    _ -> 0
  }
}

fn score(attempt: Attempt) -> Int {
  stage(attempt.status)
  * 1_000_000_000
  + int.min(attempt.recent, 999)
  * 1_000_000
  + int.min(attempt.stars, 999_999)
}

pub fn find(db: Connection, slug: String) -> Result(Attempt, Nil) {
  let assert Ok(found) =
    pog.query("select " <> columns <> " from attempts where slug = $1")
    |> pog.parameter(pog.text(slug))
    |> pog.returning(decoder())
    |> pog.execute(db)
  list.first(found.rows)
}

pub fn readme(db: Connection, id: Int) -> String {
  let assert Ok(found) =
    pog.query("select readme from attempts where id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(db)
  string.concat(found.rows)
}

pub fn mirror(line: String) -> #(String, String) {
  case list.reverse(string.split(string.trim(line), " ")) {
    [url] -> #(url, url)
    [url, ..label] -> #(string.join(list.reverse(label), " "), url)
    [] -> #("", "")
  }
}

pub fn save(
  db: Connection,
  app: App,
  attempt: Attempt,
) -> Result(String, String) {
  let name = string.trim(attempt.name)
  let slug = case attempt.id {
    0 ->
      string.lowercase(name)
      |> string.to_graphemes
      |> list.map(fn(letter) {
        case string.contains("abcdefghijklmnopqrstuvwxyz0123456789", letter) {
          True -> letter
          False -> " "
        }
      })
      |> string.concat
      |> string.split(" ")
      |> list.filter(fn(part) { part != "" })
      |> string.join("-")
    _ -> attempt.slug
  }
  let mirrors =
    string.split(string.replace(attempt.mirrors, "\r", ""), "\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { line != "" })
  use <- bool.guard(
    slug == "" || slug == "new" || slug == "compare" || string.length(name) > 60,
    Error("A name of at most 60 characters with letters or digits is required."),
  )
  use <- bool.guard(
    !list.contains(kinds, attempt.kind),
    Error("Choose a kind from the list."),
  )
  use <- bool.guard(
    !list.contains(gpus, attempt.gpu),
    Error("Choose a GPU from the list."),
  )
  use <- bool.guard(
    string.length(attempt.description) > 200
      || string.length(attempt.owner) > 60,
    Error("Description is at most 200 characters, owner at most 60."),
  )
  use <- bool.guard(
    attempt.discord != ""
      && !string.starts_with(attempt.discord, "https://discord.gg/")
      && !string.starts_with(attempt.discord, "https://discord.com/"),
    Error("The Discord link must start with https://discord.gg/."),
  )
  use <- bool.guard(
    list.length(mirrors) > 50
      || !list.all(mirrors, fn(line) {
      let url = mirror(line).1
      list.any(
        ["magnet:?", "https://", "http://", "git://"],
        string.starts_with(url, _),
      )
    }),
    Error(
      "Each mirror line must end with a magnet, https, http or git address.",
    ),
  )
  use <- bool.guard(
    string.contains(
      name <> attempt.description <> attempt.owner <> attempt.mirrors,
      "\u{0}",
    ),
    Error("Text cannot contain null characters."),
  )
  use repo <- result.try(case string.trim(attempt.repo) {
    "" -> Ok("")
    text ->
      github.repo(text)
      |> result.replace_error(
        "The GitHub repository must look like owner/name.",
      )
  })
  use fetched <- result.try(case repo {
    "" -> Ok(None)
    _ ->
      github.commits(app, repo)
      |> result.map(Some)
      |> result.replace_error("That GitHub repository could not be read.")
  })

  let saved =
    case attempt.id {
      0 ->
        pog.query(
          "insert into attempts
            (slug, name, kind, description, owner, repo, discord, mirrors, gpu)
          values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
          returning id",
        )
        |> pog.parameter(pog.text(slug))
      id ->
        pog.query(
          "update attempts set name = $2, kind = $3, description = $4,
            owner = $5, repo = $6, discord = $7, mirrors = $8, gpu = $9
          where id = $1 returning id",
        )
        |> pog.parameter(pog.int(id))
    }
    |> pog.parameter(pog.text(name))
    |> pog.parameter(pog.text(attempt.kind))
    |> pog.parameter(pog.text(string.trim(attempt.description)))
    |> pog.parameter(pog.text(string.trim(attempt.owner)))
    |> pog.parameter(pog.text(repo))
    |> pog.parameter(pog.text(attempt.discord))
    |> pog.parameter(pog.text(string.join(mirrors, "\n")))
    |> pog.parameter(pog.text(attempt.gpu))
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(db)

  case saved, fetched {
    Ok(pog.Returned(rows: [id], ..)), Some(commits) -> {
      store(db, id, commits, github.readme(app, repo), github.stats(app, repo))
      Ok(slug)
    }
    Ok(_), _ -> Ok(slug)
    Error(pog.ConstraintViolated(..)), _ ->
      Error("An attempt with that name already exists.")
    Error(_), _ -> panic as "attempt could not be saved"
  }
}

pub fn delete(db: Connection, id: Int) -> Nil {
  let assert Ok(_) =
    pog.query("delete from attempts where id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.execute(db)
  Nil
}

pub fn claim(db: Connection, id: Int) -> Bool {
  let assert Ok(claimed) =
    pog.query(
      "update attempts set checked_at = now()
      where id = $1 and checked_at < now() - interval '5 minutes'",
    )
    |> pog.parameter(pog.int(id))
    |> pog.execute(db)
  claimed.count == 1
}

pub fn refresh(db: Connection, app: App, attempt: Attempt) -> Nil {
  case github.commits(app, attempt.repo) {
    Ok(commits) ->
      store(
        db,
        attempt.id,
        commits,
        github.readme(app, attempt.repo),
        github.stats(app, attempt.repo),
      )
    Error(Nil) -> Nil
  }
}

fn store(
  db: Connection,
  id: Int,
  commits: List(github_types.Commit),
  readme: Result(String, Nil),
  stats: Result(github_types.Stats, Nil),
) -> Nil {
  let number = fn(pick) {
    pog.nullable(pog.int, option.from_result(result.map(stats, pick)))
  }
  let column = fn(pick) {
    pog.array(pog.text, list.map(commits, fn(commit) { clean(pick(commit)) }))
  }
  let assert Ok(_) =
    pog.query(
      "insert into commits (attempt_id, sha, message, author, committed_at)
      select $1::bigint, sha, message, author, date::timestamptz
      from unnest($2::text[], $3::text[], $4::text[], $5::text[])
        as fetched (sha, message, author, date)
      on conflict do nothing",
    )
    |> pog.parameter(pog.int(id))
    |> pog.parameter(column(fn(commit: github_types.Commit) { commit.sha }))
    |> pog.parameter(column(fn(commit: github_types.Commit) { commit.message }))
    |> pog.parameter(column(fn(commit: github_types.Commit) { commit.author }))
    |> pog.parameter(column(fn(commit: github_types.Commit) { commit.date }))
    |> pog.execute(db)
  let assert Ok(_) =
    pog.query(
      "update attempts set
        checked_at = now(),
        readme = left(coalesce($2, readme), 200000),
        stars = coalesce($3, stars),
        forks = coalesce($4, forks),
        issues = coalesce($5, issues),
        language = coalesce($6, language),
        pushed_at = (
          select max(committed_at) from commits where attempt_id = $1
        )
      where id = $1",
    )
    |> pog.parameter(pog.int(id))
    |> pog.parameter(pog.nullable(
      pog.text,
      option.from_result(result.map(readme, clean)),
    ))
    |> pog.parameter(number(fn(stats: github_types.Stats) { stats.stars }))
    |> pog.parameter(number(fn(stats: github_types.Stats) { stats.forks }))
    |> pog.parameter(number(fn(stats: github_types.Stats) { stats.issues }))
    |> pog.parameter(pog.nullable(
      pog.text,
      option.from_result(
        result.map(stats, fn(stats: github_types.Stats) { stats.language }),
      ),
    ))
    |> pog.execute(db)
  Nil
}

fn clean(text: String) -> String {
  string.replace(text, "\u{0}", "")
}

pub fn history(db: Connection, id: Int) -> List(Entry) {
  let assert Ok(found) =
    pog.query(
      "select status, note, extract(epoch from now() - created_at)::int
      from progress where attempt_id = $1 order by created_at desc, id desc",
    )
    |> pog.parameter(pog.int(id))
    |> pog.returning({
      use status <- decode.field(0, decode.string)
      use note <- decode.field(1, decode.string)
      use age <- decode.field(2, decode.int)
      decode.success(Entry(status:, note:, age:))
    })
    |> pog.execute(db)
  found.rows
}

pub fn record(
  db: Connection,
  id: Int,
  status: String,
  note: String,
) -> Result(Nil, String) {
  let note = string.trim(note)
  use <- bool.guard(
    !list.contains(statuses, status),
    Error("Choose a status from the list."),
  )
  use <- bool.guard(
    string.length(note) > 500 || string.contains(note, "\u{0}"),
    Error("A note can be at most 500 characters."),
  )
  let assert Ok(_) =
    pog.query(
      "with added as (
        insert into progress (attempt_id, status, note) values ($1, $2, $3)
      )
      update attempts set status = $2 where id = $1",
    )
    |> pog.parameter(pog.int(id))
    |> pog.parameter(pog.text(status))
    |> pog.parameter(pog.text(note))
    |> pog.execute(db)
  Ok(Nil)
}

pub fn commits(db: Connection, id: Int) -> List(Commit) {
  let assert Ok(found) =
    pog.query(
      "select sha, message, author,
        extract(epoch from now() - committed_at)::int, ''
      from commits where attempt_id = $1
      order by committed_at desc limit 100",
    )
    |> pog.parameter(pog.int(id))
    |> pog.returning(commit_decoder())
    |> pog.execute(db)
  found.rows
}

pub fn commit(
  db: Connection,
  app: App,
  attempt: Attempt,
  sha: String,
) -> Result(Commit, Nil) {
  let assert Ok(found) =
    pog.query(
      "select sha, message, author,
        extract(epoch from now() - committed_at)::int, coalesce(diff, '')
      from commits where attempt_id = $1 and sha = $2",
    )
    |> pog.parameter(pog.int(attempt.id))
    |> pog.parameter(pog.text(sha))
    |> pog.returning(commit_decoder())
    |> pog.execute(db)
  use commit <- result.try(list.first(found.rows))
  let assert Ok(claimed) =
    pog.query(
      "update commits set diff = ''
      where attempt_id = $1 and sha = $2 and diff is null",
    )
    |> pog.parameter(pog.int(attempt.id))
    |> pog.parameter(pog.text(sha))
    |> pog.execute(db)
  use <- bool.guard(claimed.count == 0, Ok(commit))
  let diff = case github.diff(app, attempt.repo, sha) {
    Error(Nil) -> "The diff could not be loaded from GitHub."
    Ok("") -> "This commit has no changes to show."
    Ok(diff) ->
      case bit_array.byte_size(<<diff:utf8>>) > 300_000 {
        True -> "This diff is too large to show here."
        False -> clean(diff)
      }
  }
  let assert Ok(_) =
    pog.query("update commits set diff = $3 where attempt_id = $1 and sha = $2")
    |> pog.parameter(pog.int(attempt.id))
    |> pog.parameter(pog.text(sha))
    |> pog.parameter(pog.text(diff))
    |> pog.execute(db)
  Ok(Commit(..commit, diff:))
}

fn commit_decoder() -> Decoder(Commit) {
  use sha <- decode.field(0, decode.string)
  use message <- decode.field(1, decode.string)
  use author <- decode.field(2, decode.string)
  use age <- decode.field(3, decode.int)
  use diff <- decode.field(4, decode.string)
  decode.success(Commit(sha:, message:, author:, age:, diff:))
}

fn decoder() -> Decoder(Attempt) {
  use id <- decode.field(0, decode.int)
  use slug <- decode.field(1, decode.string)
  use name <- decode.field(2, decode.string)
  use kind <- decode.field(3, decode.string)
  use description <- decode.field(4, decode.string)
  use owner <- decode.field(5, decode.string)
  use status <- decode.field(6, decode.string)
  use repo <- decode.field(7, decode.string)
  use discord <- decode.field(8, decode.string)
  use mirrors <- decode.field(9, decode.string)
  use idle <- decode.field(10, decode.int)
  use stale <- decode.field(11, decode.bool)
  use stars <- decode.field(12, decode.int)
  use forks <- decode.field(13, decode.int)
  use issues <- decode.field(14, decode.int)
  use language <- decode.field(15, decode.string)
  use recent <- decode.field(16, decode.int)
  use gpu <- decode.field(17, decode.string)
  decode.success(Attempt(
    id:,
    slug:,
    name:,
    kind:,
    description:,
    owner:,
    status:,
    repo:,
    discord:,
    mirrors:,
    idle:,
    stale:,
    stars:,
    forks:,
    issues:,
    language:,
    recent:,
    gpu:,
  ))
}
