import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import pog.{type Connection}
import vitrack/github
import vitrack/page
import vitrack/typs/github_types.{type App}
import vitrack/typs/user_types.{type User}
import vitrack/user
import wisp.{type Request, type Response}

type Unit {Second}

@external(erlang, "os", "system_time")
fn now(unit: Unit) -> Int

pub fn current(req: Request, db: Connection) -> Result(User, Nil) {
  use token <- result.try(wisp.get_cookie(req, "session", wisp.PlainText))
  user.current(db, token)
}

pub fn member(
  visitor: Result(User, Nil),
  next: fn(User) -> Response,
) -> Response {
  case visitor {
    Ok(member) -> next(member)
    Error(Nil) -> wisp.redirect("/login")
  }
}

pub fn login(req: Request, app: App) -> Response {
  let state = wisp.random_string(32)
  let post =
    wisp.get_query(req)
    |> list.key_find("post")
    |> result.try(int.parse)
    |> result.unwrap(0)

  wisp.redirect(github.authorize_url(app, state))
  |> wisp.set_cookie(
    req,
    "state",
    "state:"
      <> state
      <> ":"
      <> int.to_string(post)
      <> ":"
      <> int.to_string(now(Second)),
    wisp.Signed,
    600,
  )
}

pub fn callback(req: Request, db: Connection, app: App) -> Response {
  let query = wisp.get_query(req)
  let entered = {
    use code <- result.try(list.key_find(query, "code"))
    use state <- result.try(list.key_find(query, "state"))
    use cookie <- result.try(wisp.get_cookie(req, "state", wisp.Signed))
    case string.split(cookie, ":") {
      ["state", expected, post, issued] if expected == state -> {
        use post <- result.try(int.parse(post))
        use issued <- result.try(int.parse(issued))
        use <- bool.guard(now(Second) - issued > 600, Error(Nil))
        use profile <- result.try(github.profile(app, code))
        Ok(#(profile, post))
      } _ -> Error(Nil)
    }
  }

  case entered {
    Ok(#(profile, post)) -> {
      let member = user.save(db, profile.id, profile.login)
      let token = wisp.random_string(64)
      user.login(db, member.id, token)
      wisp.redirect(case post {
        0 -> "/community"
        _ -> "/post/" <> int.to_string(post)
      }) |> wisp.set_cookie(req, "session", token, wisp.PlainText, 2_592_000) }
    Error(Nil) -> page.problem(Error(Nil), "Login with GitHub did not work.")
  } |> wisp.set_cookie(req, "state", "", wisp.PlainText, 0)
}

pub fn logout(req: Request, db: Connection) -> Response {
  let _ = wisp.get_cookie(req, "session", wisp.PlainText) |> result.map(user.logout(db, _))
  wisp.redirect("/community") |> wisp.set_cookie(req, "session", "", wisp.PlainText, 0)
}
