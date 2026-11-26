import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/charlist.{type Charlist}
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/uri
import vitrack/typs/github_types.{
  type App, type Commit, type Profile, type Stats, Commit, Profile, Stats,
}

type Method {
  Get
  Post
}

type Option {
  Timeout(Int)
  BodyFormat(Format)
  SocketOpts(List(Option))
  Ipfamily(Family)
}

type Format {
  Binary
}

type Family {
  Inet
}

type Reply =
  Result(#(#(Dynamic, Int, Dynamic), Dynamic, BitArray), Dynamic)

const options = [BodyFormat(Binary), SocketOpts([Ipfamily(Inet)])]

@external(erlang, "httpc", "request")
fn get(
  method: Method,
  request: #(Charlist, List(#(Charlist, Charlist))),
  http: List(Option),
  options: List(Option),
) -> Reply

@external(erlang, "httpc", "request")
fn post(
  method: Method,
  request: #(Charlist, List(#(Charlist, Charlist)), Charlist, String),
  http: List(Option),
  options: List(Option),
) -> Reply

fn header(name: String, value: String) -> #(Charlist, Charlist) {
  #(charlist.from_string(name), charlist.from_string(value))
}

pub fn link(word: String) -> Bool {
  case string.lowercase(word) {
    "https://gist.github.com/" <> _ -> True
    "https://github.com/" <> path -> {
      let first =
        list.fold(["/", "?", "#"], path, fn(rest, mark) {
          case string.split_once(rest, mark) {
            Ok(#(before, _)) -> before
            Error(Nil) -> rest
          }
        })
      !list.contains(
        [
          "", "login", "logout", "session", "sessions", "settings", "signup",
          "join", "password_reset", "apps", "marketplace", "installations",
          "account", "organizations",
        ],
        first,
      )
    }
    _ -> False
  }
}

pub fn only(text: String) -> Bool {
  text
  |> string.replace("\n", " ")
  |> string.replace("\r", " ")
  |> string.replace("\t", " ")
  |> string.split(" ")
  |> list.all(fn(word) {
    let word = string.lowercase(word)
    link(word)
    || !{ string.contains(word, "://") || string.contains(word, "www.") }
  })
}

pub fn authorize_url(app: App, state: String) -> String {
  "https://github.com/login/oauth/authorize?"
  <> uri.query_to_string([#("client_id", app.id), #("state", state)])
}

pub fn profile(app: App, code: String) -> Result(Profile, Nil) {
  use token <- result.try(token(app, code))
  use res <- result.try(
    get(
      Get,
      #(charlist.from_string("https://api.github.com/user"), [
        header("authorization", "Bearer " <> token),
        header("user-agent", "vitrack"),
      ]),
      [Timeout(10_000)],
      options,
    )
    |> result.replace_error(Nil),
  )
  json.parse_bits(res.2, {
    use id <- decode.field("id", decode.int)
    use login <- decode.field("login", decode.string)
    decode.success(Profile(id:, login:))
  })
  |> result.replace_error(Nil)
}

fn token(app: App, code: String) -> Result(String, Nil) {
  use res <- result.try(
    post(
      Post,
      #(
        charlist.from_string("https://github.com/login/oauth/access_token"),
        [header("accept", "application/json")],
        charlist.from_string("application/x-www-form-urlencoded"),
        uri.query_to_string([
          #("client_id", app.id),
          #("client_secret", app.secret),
          #("code", code),
        ]),
      ),
      [Timeout(10_000)],
      options,
    )
    |> result.replace_error(Nil),
  )
  json.parse_bits(res.2, decode.at(["access_token"], decode.string))
  |> result.replace_error(Nil)
}

pub fn repo(text: String) -> Result(String, Nil) {
  let name = case string.trim(text) {
    "https://github.com/" <> rest -> rest
    other -> other
  }
  let name = case string.ends_with(name, ".git") {
    True -> string.drop_end(name, 4)
    False -> name
  }
  case string.split(name, "/") {
    [owner, project] ->
      case
        list.all([owner, project], fn(part) {
          part != ""
          && part != "."
          && part != ".."
          && list.all(string.to_graphemes(part), string.contains(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.",
            _,
          ))
        })
      {
        True -> Ok(name)
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

pub fn commits(app: App, repo: String) -> Result(List(Commit), Nil) {
  use body <- result.try(api(
    app,
    "/repos/" <> repo <> "/commits?per_page=100",
    "application/vnd.github+json",
  ))
  json.parse(
    body,
    decode.list({
      use sha <- decode.field("sha", decode.string)
      use message <- decode.subfield(["commit", "message"], decode.string)
      use author <- decode.subfield(["commit", "author", "name"], decode.string)
      use date <- decode.subfield(["commit", "author", "date"], decode.string)
      decode.success(Commit(sha:, message:, author:, date:))
    }),
  )
  |> result.replace_error(Nil)
}

pub fn stats(app: App, repo: String) -> Result(Stats, Nil) {
  use body <- result.try(api(
    app,
    "/repos/" <> repo,
    "application/vnd.github+json",
  ))
  json.parse(body, {
    use stars <- decode.field("stargazers_count", decode.int)
    use forks <- decode.field("forks_count", decode.int)
    use issues <- decode.field("open_issues_count", decode.int)
    use language <- decode.field("language", decode.optional(decode.string))
    decode.success(Stats(
      stars:,
      forks:,
      issues:,
      language: option.unwrap(language, ""),
    ))
  })
  |> result.replace_error(Nil)
}

pub fn readme(app: App, repo: String) -> Result(String, Nil) {
  api(app, "/repos/" <> repo <> "/readme", "application/vnd.github.raw")
}

pub fn diff(app: App, repo: String, sha: String) -> Result(String, Nil) {
  api(
    app,
    "/repos/" <> repo <> "/commits/" <> sha,
    "application/vnd.github.diff",
  )
}

fn api(app: App, path: String, accept: String) -> Result(String, Nil) {
  let key =
    bit_array.base64_encode(<<app.id:utf8, ":":utf8, app.secret:utf8>>, True)
  case
    get(
      Get,
      #(charlist.from_string("https://api.github.com" <> path), [
        header("authorization", "Basic " <> key),
        header("user-agent", "vitrack"),
        header("accept", accept),
      ]),
      [Timeout(10_000)],
      options,
    )
  {
    Ok(#(#(_, 200, _), _, body)) -> bit_array.to_string(body)
    _ -> Error(Nil)
  }
}
