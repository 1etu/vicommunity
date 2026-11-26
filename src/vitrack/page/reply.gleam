import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import lustre/attribute
import lustre/element/html
import pog.{type Connection}
import vitrack/comment
import vitrack/notice
import vitrack/page
import vitrack/typs/user_types.{type User}
import wisp.{type Request, type Response}

pub fn form(db: Connection, user: User, id: String) -> Response {
  case int.parse(id) |> result.try(comment.find(db, user.id, _)) {
    Error(Nil) -> wisp.not_found()
    Ok(parent) ->
      page.frame("reply | vitrack", "/community", Ok(user), [
        html.p(
          [attribute.class("byline")],
          page.byline(parent.github_id, parent.login, parent.age),
        ),
        html.div([attribute.class("text")], page.text(parent.body)),
        html.form(
          [attribute.method("post"), attribute.action("/reply/" <> id)],
          [
            html.textarea(
              [
                attribute.name("text"),
                attribute.rows(6),
                attribute.required(True),
                attribute.autofocus(True),
                attribute.aria_label("reply"),
              ],
              "",
            ),
            html.input([attribute.type_("submit"), attribute.value("reply")]),
          ],
        ),
      ])
  }
}

pub fn create(
  req: Request,
  db: Connection,
  user: User,
  id: String,
) -> Response {
  use form <- wisp.require_form(req)
  let body = list.key_find(form.values, "text") |> result.unwrap("")
  use <- bool.lazy_guard(notice.removes(db, user.id, body), fn() {
    wisp.redirect("/notices")
  })
  case int.parse(id) |> result.try(comment.find(db, user.id, _)) {
    Error(Nil) -> wisp.not_found()
    Ok(parent) ->
      case comment.create(db, user.id, parent.post_id, parent.id, body) {
        Ok(created) ->
          wisp.redirect(
            "/post/"
            <> int.to_string(parent.post_id)
            <> "#c"
            <> int.to_string(created),
          )
        Error(message) -> page.problem(Ok(user), message)
      }
  }
}
