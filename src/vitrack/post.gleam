import gleam/bool
import gleam/dynamic/decode.{type Decoder}
import gleam/result
import gleam/string
import pog.{type Connection}
import vitrack/language
import vitrack/typs/post_types.{type Post, Post}

const columns =
  "p.id, p.title, p.body, p.score, p.comment_count,
  extract(epoch from now() - p.created_at)::int, p.deleted,
  u.id, u.login, u.github_id, v.value is not null,
  p.pinned, p.locked, u.banned"

const joins =
  "join users u on u.id = p.user_id
  left join post_votes v on v.post_id = p.id and v.user_id = $1"

pub fn hot(db: Connection, viewer: Int, page: Int) -> List(Post) {
  select(db, viewer, page, "select " <> columns <> "
    from (
      select * from posts where not deleted
      order by pinned desc, created_at desc limit 500
    ) p " <> joins <> "
    order by
      p.pinned desc,
      (p.score - 1) / power(extract(epoch from now() - p.created_at) / 3600 + 2, 1.8) desc,
      p.created_at desc
    limit 31 offset $2")
}

pub fn newest(db: Connection, viewer: Int, page: Int) -> List(Post) {
  select(db, viewer, page, "select " <> columns <> "
    from posts p " <> joins <> "
    where not p.deleted
    order by p.created_at desc
    limit 31 offset $2")
}

fn select(db: Connection, viewer: Int, page: Int, sql: String) -> List(Post) {
  let assert Ok(found) =
    pog.query(sql)
    |> pog.parameter(pog.int(viewer))
    |> pog.parameter(pog.int({ page - 1 } * 30))
    |> pog.returning(decoder())
    |> pog.execute(db)
  found.rows
}

pub fn find(db: Connection, viewer: Int, id: Int) -> Result(Post, Nil) {
  let assert Ok(found) =
    pog.query("select " <> columns <> "
      from posts p " <> joins <> "
      where p.id = $2")
    |> pog.parameter(pog.int(viewer))
    |> pog.parameter(pog.int(id))
    |> pog.returning(decoder())
    |> pog.execute(db)
  case found.rows {
    [post] -> Ok(post)
    _ -> Error(Nil)
  }
}

pub fn allowed(
  db: Connection,
  user: Int,
  title: String,
  body: String,
) -> Result(Nil, String) {
  use _ <- result.try(valid(string.trim(title), string.trim(body)))
  let assert Ok(recent) =
    pog.query(
      "select 1 from posts
      where user_id = $1 and created_at > now() - interval '1 minute'
      limit 1",
    )
    |> pog.parameter(pog.int(user))
    |> pog.execute(db)
  case recent.count {
    0 -> Ok(Nil)
    _ -> Error("You're posting too fast. Please slow down. Thanks.")
  }
}

pub fn create(
  db: Connection,
  user: Int,
  title: String,
  body: String,
) -> Result(Int, String) {
  let title = string.trim(title)
  let body = string.trim(body)
  use _ <- result.try(valid(title, body))
  let assert Ok(created) =
    pog.transaction(db, fn(db) {
      use _ <- result.try(
        pog.query("select pg_advisory_xact_lock($1)::text")
        |> pog.parameter(pog.int(user))
        |> pog.execute(db),
      )
      pog.query(
        "with created as (
          insert into posts (user_id, title, body)
          select $1::bigint, $2::text, $3::text
          where not exists (
            select 1 from posts
            where user_id = $1 and created_at > now() - interval '1 minute'
          )
          returning id
        ), voted as (
          insert into post_votes (post_id, user_id, value)
          select id, $1, 1 from created
        )
        select id from created",
      )
      |> pog.parameter(pog.int(user))
      |> pog.parameter(pog.text(title))
      |> pog.parameter(pog.text(body))
      |> pog.returning(decode.at([0], decode.int))
      |> pog.execute(db)
    })
  case created.rows {
    [id] -> Ok(id)
    _ -> Error("You're posting too fast. Please slow down. Thanks.")
  }
}

fn valid(title: String, body: String) -> Result(Nil, String) {
  use <- bool.guard(title == "", Error("A title is required."))
  use <- bool.guard(
    string.length(title) > 100 || string.byte_size(title) > 400,
    Error("Titles can be at most 100 characters."),
  )
  use <- bool.guard(
    string.length(body) > 10_000 || string.byte_size(body) > 40_000,
    Error("Text can be at most 10,000 characters."),
  )
  use <- bool.guard(
    string.contains(title <> body, "\u{0}"),
    Error("Text cannot contain null characters."),
  )
  language.check(title <> "\n" <> body)
}

pub fn vote(db: Connection, user: Int, id: Int, value: Int) -> Nil {
  let assert Ok(_) =
    pog.transaction(db, fn(db) {
      use locked <- result.try(
        pog.query(
          "select 1 from posts where id = $1 and not deleted for update",
        )
        |> pog.parameter(pog.int(id))
        |> pog.execute(db),
      )
      use <- bool.guard(locked.count == 0, Ok(Nil))
      use _ <- result.try(
        pog.query(case value {
          1 ->
            "insert into post_votes (post_id, user_id, value)
            values ($1, $2, 1) on conflict do nothing"
          _ -> "delete from post_votes where post_id = $1 and user_id = $2"
        })
        |> pog.parameter(pog.int(id))
        |> pog.parameter(pog.int(user))
        |> pog.execute(db),
      )
      pog.query(
        "update posts set score = (
          select coalesce(sum(value), 0) from post_votes where post_id = $1
        ) where id = $1",
      )
      |> pog.parameter(pog.int(id))
      |> pog.execute(db)
      |> result.replace(Nil)
    })
  Nil
}

pub fn delete(db: Connection, id: Int) -> Nil {
  let assert Ok(_) =
    pog.query(
      "update posts set deleted = true, title = '', body = ''
      where id = $1",
    )
    |> pog.parameter(pog.int(id))
    |> pog.execute(db)
  Nil
}

pub fn pin(db: Connection, id: Int, pinned: Bool) -> Nil {
  let assert Ok(_) =
    pog.query("update posts set pinned = $2 where id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.parameter(pog.bool(pinned))
    |> pog.execute(db)
  Nil
}

pub fn lock(db: Connection, id: Int, locked: Bool) -> Nil {
  let assert Ok(_) =
    pog.query("update posts set locked = $2 where id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.parameter(pog.bool(locked))
    |> pog.execute(db)
  Nil
}

fn decoder() -> Decoder(Post) {
  use id <- decode.field(0, decode.int)
  use title <- decode.field(1, decode.string)
  use body <- decode.field(2, decode.string)
  use score <- decode.field(3, decode.int)
  use comments <- decode.field(4, decode.int)
  use age <- decode.field(5, decode.int)
  use deleted <- decode.field(6, decode.bool)
  use user_id <- decode.field(7, decode.int)
  use login <- decode.field(8, decode.string)
  use github_id <- decode.field(9, decode.int)
  use voted <- decode.field(10, decode.bool)
  use pinned <- decode.field(11, decode.bool)
  use locked <- decode.field(12, decode.bool)
  use banned <- decode.field(13, decode.bool)
  decode.success(Post(
    id:,
    title:,
    body:,
    score:,
    comments:,
    age:,
    deleted:,
    user_id:,
    login:,
    github_id:,
    voted:,
    pinned:,
    locked:,
    banned:,
  ))
}
