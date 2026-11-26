import gleam/int
import gleam/list
import lustre/attribute
import lustre/element/html
import pog.{type Connection}
import vitrack/notice
import vitrack/page
import vitrack/typs/user_types.{type User, User}
import wisp.{type Response}

pub fn show(db: Connection, user: User) -> Response {
  let notices = notice.of(db, user.id)

  page.frame(
    "notices | vitrack",
    "/community",
    Ok(User(..user, notices: list.length(notices))),
    case notices {
      [] -> [html.p([], [html.text("No notices.")])]
      _ ->
        list.map(notices, fn(notice) {
          html.section([attribute.class("notice")], [
            html.p([], [
              html.text(
                "Your message was deleted. Only links to GitHub are allowed here. This is what you wrote:",
              ),
            ]),
            html.div([attribute.class("text")], page.text(notice.body)),
            html.form(
              [
                attribute.method("post"),
                attribute.action(
                  "/notice/" <> int.to_string(notice.id) <> "/dismiss",
                ),
              ],
              [html.button([], [html.text("dismiss")])],
            ),
          ])
        })
    },
  )
}

pub fn dismiss(db: Connection, user: User, id: String) -> Response {
  case int.parse(id) {
    Ok(id) -> {
      notice.dismiss(db, user.id, id)
      wisp.redirect("/notices")
    }
    Error(Nil) -> wisp.not_found()
  }
}
