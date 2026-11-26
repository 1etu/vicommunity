import gleam/http
import gleam/http/response
import gleam/string
import pog.{type Connection}
import vitrack/page/attempts
import vitrack/page/auth
import vitrack/page/community
import vitrack/page/home
import vitrack/page/notices
import vitrack/page/polls
import vitrack/page/reply
import vitrack/page/submit
import vitrack/page/thread
import vitrack/typs/github_types.{type App}
import wisp.{type Request, type Response}

pub fn handle(req: Request, db: Connection, app: App) -> Response {
  route(req, db, app)
  |> response.set_header(
    "content-security-policy",
    "default-src 'none'; style-src 'self'; img-src 'self' https://avatars.githubusercontent.com; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
  )
  |> response.set_header("x-content-type-options", "nosniff")
  |> response.set_header("referrer-policy", "same-origin")
}

fn route(req: Request, db: Connection, app: App) -> Response {
  use <- wisp.rescue_crashes
  let assert Ok(priv) = wisp.priv_directory("vitrack")
  use <- files(req, "/static/", priv <> "/static", "max-age=3600")
  use <- files(req, "/uploads/", "data/uploads", "max-age=31536000, immutable")
  use req <- wisp.csrf_known_header_protection(req)
  let req =
    wisp.set_max_body_size(req, 200_000)
    |> wisp.set_max_files_size(24_000_000)
  let user = auth.current(req, db)

  case req.method, wisp.path_segments(req) {
    http.Get, [] -> home.render(user)
    http.Get, ["attempts"] -> attempts.render(req, db, app, user)
    http.Get, ["attempts", "compare"] -> attempts.compare(db, app, user)
    http.Get, ["attempts", "new"] -> auth.member(user, attempts.form)
    http.Post, ["attempts"] ->
      auth.member(user, attempts.create(req, db, app, _))
    http.Get, ["attempts", slug] -> attempts.show(db, app, user, slug, "")
    http.Get, ["attempts", slug, "edit"] ->
      auth.member(user, attempts.edit(db, _, slug))
    http.Get, ["attempts", slug, tab] -> attempts.show(db, app, user, slug, tab)
    http.Get, ["attempts", slug, "commits", sha] ->
      attempts.commit(db, app, user, slug, sha)
    http.Post, ["attempts", slug] ->
      auth.member(user, attempts.update(req, db, app, _, slug))
    http.Post, ["attempts", slug, "progress"] ->
      auth.member(user, attempts.record(req, db, _, slug))
    http.Post, ["attempts", slug, "delete"] ->
      auth.member(user, attempts.delete(db, _, slug))
    http.Get, ["community"] -> community.hot(req, db, user)
    http.Get, ["community", "new"] -> community.newest(req, db, user)
    http.Get, ["submit"] -> auth.member(user, submit.form)
    http.Post, ["submit"] -> auth.member(user, submit.create(req, db, _))
    http.Get, ["post", id] -> thread.show(db, user, id)
    http.Post, ["post", id, "vote"] ->
      auth.member(user, thread.vote(req, db, _, id))
    http.Post, ["post", id, "comment"] ->
      auth.member(user, thread.add(req, db, _, id))
    http.Post, ["post", id, "delete"] ->
      auth.member(user, thread.delete(db, _, id))
    http.Post, ["post", id, "pin"] ->
      auth.member(user, thread.pin(db, _, id, True))
    http.Post, ["post", id, "unpin"] ->
      auth.member(user, thread.pin(db, _, id, False))
    http.Post, ["post", id, "close"] ->
      auth.member(user, thread.lock(db, _, id, True))
    http.Post, ["post", id, "open"] ->
      auth.member(user, thread.lock(db, _, id, False))
    http.Post, ["post", id, "ban"] ->
      auth.member(user, thread.ban(db, _, id, True))
    http.Post, ["post", id, "unban"] ->
      auth.member(user, thread.ban(db, _, id, False))
    http.Post, ["comment", id, "ban"] ->
      auth.member(user, thread.ban_comment(db, _, id, True))
    http.Post, ["comment", id, "unban"] ->
      auth.member(user, thread.ban_comment(db, _, id, False))
    http.Get, ["reply", id] -> auth.member(user, reply.form(db, _, id))
    http.Post, ["reply", id] -> auth.member(user, reply.create(req, db, _, id))
    http.Post, ["comment", id, "vote"] ->
      auth.member(user, thread.vote_comment(req, db, _, id))
    http.Post, ["comment", id, "delete"] ->
      auth.member(user, thread.delete_comment(db, _, id))
    http.Get, ["polls"] -> polls.render(db, user)
    http.Get, ["polls", "new"] -> auth.member(user, polls.form)
    http.Post, ["polls"] -> auth.member(user, polls.create(req, db, _))
    http.Post, ["polls", "vote"] -> auth.member(user, polls.vote(req, db, _))
    http.Post, ["polls", id, "close"] ->
      auth.member(user, polls.close(db, _, id, True))
    http.Post, ["polls", id, "open"] ->
      auth.member(user, polls.close(db, _, id, False))
    http.Post, ["polls", id, "delete"] ->
      auth.member(user, polls.delete(db, _, id))
    http.Get, ["notices"] -> auth.member(user, notices.show(db, _))
    http.Post, ["notice", id, "dismiss"] ->
      auth.member(user, notices.dismiss(db, _, id))
    http.Get, ["login"] -> auth.login(req, app)
    http.Get, ["auth", "github", "callback"] -> auth.callback(req, db, app)
    http.Post, ["logout"] -> auth.logout(req, db)
    _, _ -> wisp.not_found()
  }
}

fn files(
  req: Request,
  prefix: String,
  directory: String,
  cache: String,
  next: fn() -> Response,
) -> Response {
  case string.starts_with(req.path, prefix) {
    False -> next()
    True -> {
      let res =
        wisp.serve_static(
          req,
          under: prefix,
          from: directory,
          next: wisp.not_found,
        )
      case res.status < 400 {
        True -> response.set_header(res, "cache-control", cache)
        False -> res
      }
    }
  }
}
