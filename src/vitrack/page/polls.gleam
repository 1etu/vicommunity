import gleam/bool
import gleam/http/response.{Response}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import pog.{type Connection}
import vitrack/page
import vitrack/poll
import vitrack/typs/poll_types.{type Poll}
import vitrack/typs/user_types.{type User, User}
import wisp.{type Request, type Response}

pub fn render(db: Connection, user: Result(User, Nil)) -> Response {
  let viewer = case user {
    Ok(user) -> user.id
    Error(Nil) -> 0
  }

  page.frame("polls | vitrack", "/polls", user, [
    case user {
      Ok(User(admin: True, ..)) ->
        html.p([], [
          html.a([attribute.href("/polls/new")], [html.text("new poll")]),
        ])
      _ -> element.none()
    },
    ..list.map(poll.all(db, viewer), show(_, user))
  ])
}

fn show(found: Poll, user: Result(User, Nil)) -> Element(a) {
  let total = int.sum(list.map(found.choices, fn(choice) { choice.votes }))
  let id = int.to_string(found.id)

  html.section([attribute.class("poll")], [
    html.h2([], [html.text(found.question)]),
    html.div(
      [attribute.class("byline")],
      list.flatten([
        [
          html.text(
            "by "
            <> found.login
            <> " | "
            <> int.to_string(total)
            <> case total {
              1 -> " vote"
              _ -> " votes"
            }
            <> case found.closed {
              True -> " | closed"
              False -> ""
            },
          ),
        ],
        case user {
          Ok(User(admin: True, ..)) -> [
            html.text(" | "),
            act(
              "/polls/"
                <> id
                <> case found.closed {
                True -> "/open"
                False -> "/close"
              },
              case found.closed {
                True -> "open"
                False -> "close"
              },
            ),
            html.text(" | "),
            act("/polls/" <> id <> "/delete", "delete"),
          ]
          _ -> []
        },
      ]),
    ),
    html.form([attribute.method("post"), attribute.action("/polls/vote")], [
      html.table(
        [attribute.class("list")],
        list.map(found.choices, fn(choice) {
          let filled = case total {
            0 -> 0
            _ -> choice.votes * 30 / total
          }
          html.tr([], [
            html.td([], [
              case user, found.closed {
                _, True -> element.none()
                Ok(_), False ->
                  html.button(
                    [
                      attribute.name("option"),
                      attribute.value(int.to_string(choice.id)),
                      attribute.classes([#("voted", found.mine == choice.id)]),
                    ],
                    [
                      html.text(case found.mine == choice.id {
                        True -> "voted"
                        False -> "vote"
                      }),
                    ],
                  )
                Error(Nil), False ->
                  html.a([attribute.href("/login")], [html.text("vote")])
              },
            ]),
            html.td([], [html.text(choice.label)]),
            html.td([attribute.class("bar")], [
              html.text(
                "["
                <> string.repeat("#", filled)
                <> string.repeat(".", 30 - filled)
                <> "]",
              ),
            ]),
            html.td([], [
              html.text(
                int.to_string(choice.votes)
                <> case total {
                  0 -> ""
                  _ -> "  " <> int.to_string(choice.votes * 100 / total) <> "%"
                },
              ),
            ]),
          ])
        }),
      ),
    ]),
  ])
}

fn act(action: String, label: String) -> Element(a) {
  html.form([attribute.method("post"), attribute.action(action)], [
    html.button([], [html.text(label)]),
  ])
}

pub fn form(user: User) -> Response {
  use <- bool.guard(!user.admin, wisp.not_found())
  fields(user, "", "", "")
}

fn fields(
  user: User,
  problem: String,
  question: String,
  options: String,
) -> Response {
  page.frame("new poll | vitrack", "/polls", Ok(user), [
    case problem {
      "" -> element.none()
      _ -> html.p([attribute.class("problem")], [html.text(problem)])
    },
    html.form(
      [
        attribute.class("submit"),
        attribute.method("post"),
        attribute.action("/polls"),
      ],
      [
        html.label([attribute.for("question")], [html.text("question")]),
        html.input([
          attribute.id("question"),
          attribute.name("question"),
          attribute.value(question),
          attribute.maxlength(200),
          attribute.required(True),
        ]),
        html.label([attribute.for("options")], [html.text("options")]),
        html.textarea(
          [
            attribute.id("options"),
            attribute.name("options"),
            attribute.rows(8),
            attribute.placeholder("one option per line"),
          ],
          options,
        ),
        html.span([], []),
        html.input([attribute.type_("submit"), attribute.value("create")]),
      ],
    ),
  ])
}

pub fn create(req: Request, db: Connection, user: User) -> Response {
  use <- bool.guard(!user.admin, wisp.not_found())
  use form <- wisp.require_form(req)
  let field = fn(name) { list.key_find(form.values, name) |> result.unwrap("") }
  case poll.create(db, user.id, field("question"), field("options")) {
    Ok(Nil) -> wisp.redirect("/polls")
    Error(problem) -> {
      let res = fields(user, problem, field("question"), field("options"))
      Response(..res, status: 422)
    }
  }
}

pub fn vote(req: Request, db: Connection, user: User) -> Response {
  use form <- wisp.require_form(req)
  case list.key_find(form.values, "option") |> result.try(int.parse) {
    Ok(choice) -> {
      poll.vote(db, user.id, choice)
      wisp.redirect("/polls")
    }
    Error(Nil) -> wisp.bad_request("unknown option")
  }
}

pub fn close(db: Connection, user: User, id: String, closed: Bool) -> Response {
  moderate(user, id, poll.close(db, _, closed))
}

pub fn delete(db: Connection, user: User, id: String) -> Response {
  moderate(user, id, poll.delete(db, _))
}

fn moderate(user: User, id: String, change: fn(Int) -> Nil) -> Response {
  case user.admin, int.parse(id) {
    True, Ok(number) -> {
      change(number)
      wisp.redirect("/polls")
    }
    _, _ -> wisp.not_found()
  }
}
