import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import pog.{type Connection}
import vitrack/comment
import vitrack/notice
import vitrack/page
import vitrack/photo
import vitrack/post
import vitrack/typs/comment_types.{type Comment}
import vitrack/typs/user_types.{type User}
import vitrack/user
import wisp.{type Request, type Response}

pub fn show(db: Connection, user: Result(User, Nil), id: String) -> Response {
  let viewer = case user {
    Ok(user) -> user.id
    Error(Nil) -> 0
  }
  case int.parse(id) |> result.try(post.find(db, viewer, _)) {
    Error(Nil) -> wisp.not_found()
    Ok(found) ->
      page.frame(found.title <> " | vitrack", "/community", user, [
        html.ol([attribute.class("posts")], [page.row(found, user, [])]),
        html.div([attribute.class("text")], page.text(found.body)),
        html.div(
          [attribute.class("photos")],
          list.map(photo.of(db, found.id), fn(photo) {
            html.img([
              attribute.src("/uploads/" <> photo.file),
              attribute.alt(""),
              attribute.width(photo.width),
              attribute.height(photo.height),
              attribute.loading("lazy"),
            ])
          }),
        ),
        case user, found.deleted {
          _, True -> element.none()
          Ok(user), False ->
            html.div([attribute.class("text")], [
              html.div(
                [attribute.class("byline")],
                list.flatten([
                  case user.admin || user.id == found.user_id {
                    True -> [act("/post/" <> id <> "/delete", "delete")]
                    False -> []
                  },
                  case user.admin {
                    True -> {
                      let pin = case found.pinned {
                        True -> "unpin"
                        False -> "pin"
                      }
                      let close = case found.locked {
                        True -> "open"
                        False -> "close"
                      }
                      let ban = case found.banned {
                        True -> "unban"
                        False -> "ban"
                      }
                      [
                        html.text(" | "),
                        act("/post/" <> id <> "/" <> pin, pin),
                        html.text(" | "),
                        act("/post/" <> id <> "/" <> close, close),
                        html.text(" | "),
                        act(
                          "/post/" <> id <> "/" <> ban,
                          ban <> " " <> found.login,
                        ),
                      ]
                    }
                    False -> []
                  },
                ]),
              ),
              case found.locked {
                True -> html.p([], [html.text("Comments are closed.")])
                False ->
                  html.form(
                    [
                      attribute.method("post"),
                      attribute.action("/post/" <> id <> "/comment"),
                    ],
                    [
                      html.textarea(
                        [
                          attribute.name("text"),
                          attribute.rows(6),
                          attribute.required(True),
                          attribute.aria_label("comment"),
                        ],
                        "",
                      ),
                      html.input([
                        attribute.type_("submit"),
                        attribute.value("add comment"),
                      ]),
                    ],
                  )
              },
            ])
          Error(Nil), False if found.locked ->
            html.p([], [html.text("Comments are closed.")])
          Error(Nil), False ->
            html.p([], [
              html.a([attribute.href("/login?post=" <> id)], [
                html.text("login to comment"),
              ]),
            ])
        },
        thread(comment.tree(db, viewer, found.id), user, found.locked),
      ])
  }
}

fn thread(
  comments: List(Comment),
  user: Result(User, Nil),
  locked: Bool,
) -> Element(a) {
  html.ol(
    [attribute.class("comments")],
    list.map(comments, fn(comment) {
      let id = int.to_string(comment.id)
      let post = int.to_string(comment.post_id)
      html.li([attribute.id("c" <> id)], [
        case comment.deleted {
          True -> html.p([], [html.text("[deleted]")])
          False ->
            html.div([], [
              case user {
                Ok(_) ->
                  html.form(
                    [
                      attribute.class("votes"),
                      attribute.method("post"),
                      attribute.action("/comment/" <> id <> "/vote"),
                    ],
                    [
                      arrow("▲", "upvote", 1, comment.vote),
                      html.text(int.to_string(comment.score)),
                      arrow("▼", "downvote", -1, comment.vote),
                    ],
                  )
                Error(Nil) ->
                  html.div([attribute.class("votes")], [
                    html.a(
                      [
                        attribute.href("/login?post=" <> post),
                        attribute.title("upvote"),
                      ],
                      [html.text("▲")],
                    ),
                    html.text(int.to_string(comment.score)),
                    html.a(
                      [
                        attribute.href("/login?post=" <> post),
                        attribute.title("downvote"),
                      ],
                      [html.text("▼")],
                    ),
                  ])
              },
              html.div([], [
                html.div(
                  [attribute.class("byline")],
                  list.flatten([
                    page.byline(comment.github_id, comment.login, comment.age),
                    case comment.depth < 10 && !locked {
                      True -> [
                        html.text(" | "),
                        html.a(
                          [
                            attribute.href(case user {
                              Ok(_) -> "/reply/" <> id
                              Error(Nil) -> "/login?post=" <> post
                            }),
                          ],
                          [html.text("reply")],
                        ),
                      ]
                      False -> []
                    },
                    case user {
                      Ok(user) if user.admin || user.id == comment.user_id -> [
                        html.text(" | "),
                        act("/comment/" <> id <> "/delete", "delete"),
                      ]
                      _ -> []
                    },
                    case user {
                      Ok(user) if user.admin -> [
                        html.text(" | "),
                        act(
                          "/comment/"
                            <> id
                            <> case comment.banned {
                            True -> "/unban"
                            False -> "/ban"
                          },
                          case comment.banned {
                            True -> "unban"
                            False -> "ban"
                          },
                        ),
                      ]
                      _ -> []
                    },
                  ]),
                ),
                html.div([attribute.class("text")], page.text(comment.body)),
              ]),
            ])
        },
        thread(comment.replies, user, locked),
      ])
    }),
  )
}

fn arrow(symbol: String, title: String, value: Int, cast: Int) -> Element(a) {
  html.button(
    [
      attribute.name("value"),
      attribute.value(case cast == value {
        True -> "0"
        False -> int.to_string(value)
      }),
      attribute.title(title),
      attribute.classes([#("voted", cast == value)]),
    ],
    [html.text(symbol)],
  )
}

fn act(action: String, label: String) -> Element(a) {
  html.form([attribute.method("post"), attribute.action(action)], [
    html.button([], [html.text(label)]),
  ])
}

pub fn pin(db: Connection, admin: User, id: String, pinned: Bool) -> Response {
  moderate(admin, id, post.pin(db, _, pinned))
}

pub fn lock(db: Connection, admin: User, id: String, locked: Bool) -> Response {
  moderate(admin, id, post.lock(db, _, locked))
}

pub fn ban(db: Connection, admin: User, id: String, banned: Bool) -> Response {
  moderate(admin, id, fn(number) {
    case post.find(db, 0, number) {
      Ok(found) -> user.ban(db, found.user_id, banned)
      Error(Nil) -> Nil
    }
  })
}

pub fn ban_comment(
  db: Connection,
  admin: User,
  id: String,
  banned: Bool,
) -> Response {
  case admin.admin, int.parse(id) |> result.try(comment.find(db, 0, _)) {
    True, Ok(found) -> {
      user.ban(db, found.user_id, banned)
      wisp.redirect("/post/" <> int.to_string(found.post_id))
    }
    _, _ -> wisp.not_found()
  }
}

fn moderate(admin: User, id: String, change: fn(Int) -> Nil) -> Response {
  case admin.admin, int.parse(id) {
    True, Ok(number) -> {
      change(number)
      wisp.redirect("/post/" <> int.to_string(number))
    }
    _, _ -> wisp.not_found()
  }
}

pub fn vote(req: Request, db: Connection, user: User, id: String) -> Response {
  use form <- wisp.require_form(req)
  case int.parse(id), list.key_find(form.values, "value") {
    Ok(id), Ok("1") -> voted(db, user, id, 1, form)
    Ok(id), Ok("0") -> voted(db, user, id, 0, form)
    _, _ -> wisp.bad_request("unknown vote")
  }
}

fn voted(
  db: Connection,
  user: User,
  id: Int,
  value: Int,
  form: wisp.FormData,
) -> Response {
  post.vote(db, user.id, id, value)
  let number =
    list.key_find(form.values, "page")
    |> result.try(int.parse)
    |> result.unwrap(1)
    |> int.to_string
  let id = int.to_string(id)
  wisp.redirect(case list.key_find(form.values, "from") {
    Ok("hot") -> "/community?page=" <> number <> "#p" <> id
    Ok("new") -> "/community/new?page=" <> number <> "#p" <> id
    _ -> "/post/" <> id
  })
}

pub fn add(req: Request, db: Connection, user: User, id: String) -> Response {
  use form <- wisp.require_form(req)
  let body = list.key_find(form.values, "text") |> result.unwrap("")
  use <- bool.lazy_guard(notice.removes(db, user.id, body), fn() {
    wisp.redirect("/notices")
  })
  case int.parse(id) {
    Error(Nil) -> wisp.not_found()
    Ok(post_id) ->
      case comment.create(db, user.id, post_id, 0, body) {
        Ok(created) ->
          wisp.redirect("/post/" <> id <> "#c" <> int.to_string(created))
        Error(message) -> page.problem(Ok(user), message)
      }
  }
}

pub fn delete(db: Connection, user: User, id: String) -> Response {
  case int.parse(id) |> result.try(post.find(db, user.id, _)) {
    Ok(found) if user.admin || user.id == found.user_id -> {
      post.delete(db, found.id)
      photo.delete(db, found.id)
      wisp.redirect("/community")
    }
    _ -> wisp.not_found()
  }
}

pub fn vote_comment(
  req: Request,
  db: Connection,
  user: User,
  id: String,
) -> Response {
  use form <- wisp.require_form(req)
  let value = case list.key_find(form.values, "value") {
    Ok("1") -> Ok(1)
    Ok("0") -> Ok(0)
    Ok("-1") -> Ok(-1)
    _ -> Error(Nil)
  }
  case int.parse(id), value {
    Ok(number), Ok(value) ->
      case comment.vote(db, user.id, number, value) {
        Ok(post_id) ->
          wisp.redirect("/post/" <> int.to_string(post_id) <> "#c" <> id)
        Error(Nil) -> wisp.not_found()
      }
    _, _ -> wisp.bad_request("unknown vote")
  }
}

pub fn delete_comment(db: Connection, user: User, id: String) -> Response {
  case int.parse(id) |> result.try(comment.find(db, user.id, _)) {
    Ok(found) if user.admin || user.id == found.user_id -> {
      comment.delete(db, found.id)
      wisp.redirect("/post/" <> int.to_string(found.post_id))
    }
    _ -> wisp.not_found()
  }
}
