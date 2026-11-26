import gleam/int
import gleam/list
import gleam/result
import lustre/attribute
import lustre/element
import lustre/element/html
import pog.{type Connection}
import vitrack/page
import vitrack/post
import vitrack/typs/post_types.{type Post}
import vitrack/typs/user_types.{type User}
import wisp.{type Request, type Response}

pub fn hot(req: Request, db: Connection, user: Result(User, Nil)) -> Response {
  show(req, db, user, "hot", "/community", post.hot)
}

pub fn newest(
  req: Request,
  db: Connection,
  user: Result(User, Nil),
) -> Response {
  show(req, db, user, "new", "/community/new", post.newest)
}

fn show(
  req: Request,
  db: Connection,
  user: Result(User, Nil),
  sort: String,
  path: String,
  fetch: fn(Connection, Int, Int) -> List(Post),
) -> Response {
  let number =
    wisp.get_query(req)
    |> list.key_find("page")
    |> result.try(int.parse)
    |> result.unwrap(1)
    |> int.max(1)
    |> int.min(10_000)
  let posts =
    fetch(
      db,
      case user {
        Ok(user) -> user.id
        Error(Nil) -> 0
      },
      number,
    )

  page.frame("community | vitrack", "/community", user, [
    html.p([], [
      html.a([attribute.href("/community")], [html.text("hot")]),
      html.text(" | "),
      html.a([attribute.href("/community/new")], [html.text("new")]),
      html.text(" | "),
      html.a([attribute.href("/submit")], [html.text("submit")]),
    ]),
    case posts {
      [] -> html.p([], [html.text("Nothing here yet.")])
      _ ->
        html.ol(
          [attribute.class("posts")],
          list.take(posts, 30)
            |> list.map(
              page.row(_, user, [
                #("from", sort),
                #("page", int.to_string(number)),
              ]),
            ),
        )
    },
    case list.length(posts) > 30 {
      True ->
        html.p([], [
          html.a(
            [attribute.href(path <> "?page=" <> int.to_string(number + 1))],
            [
              html.text("more"),
            ],
          ),
        ])
      False -> element.none()
    },
  ])
}
