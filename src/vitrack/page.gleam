import gleam/http/response.{Response}
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import simplifile
import vitrack/github
import vitrack/typs/post_types.{type Post}
import vitrack/typs/user_types.{type User}
import vitrack/user
import wisp.{type Response}

pub fn frame(
  title: String,
  tab: String,
  user: Result(User, Nil),
  body: List(Element(a)),
) -> Response {
  layout("", title, tab, user, body)
}

pub fn wide(
  title: String,
  tab: String,
  user: Result(User, Nil),
  body: List(Element(a)),
) -> Response {
  layout("compact", title, tab, user, body)
}

fn layout(
  class: String,
  title: String,
  tab: String,
  user: Result(User, Nil),
  body: List(Element(a)),
) -> Response {
  let assert Ok(priv) = wisp.priv_directory("vitrack")
  let assert Ok(sheet) = simplifile.file_info(priv <> "/static/style.css")

  html.html([attribute.lang("en")], [
    html.head([], [
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.title([], title),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href(
          "/static/style.css?v=" <> int.to_string(sheet.mtime_seconds),
        ),
      ]),
      html.link([attribute.rel("icon"), attribute.href("/static/favicon.ico")]),
      html.link([
        attribute.rel("apple-touch-icon"),
        attribute.href("/static/apple-touch-icon.png"),
      ]),
    ]),
    html.body([attribute.class(class)], [
      html.header([], [
        html.a([attribute.href("/")], [
          html.img([
            attribute.src("/static/vi.webp"),
            attribute.alt("VI"),
            attribute.width(90),
            attribute.height(70),
          ]),
        ]),
        html.h1([], [html.text("TRACK.ORG")]),
        html.p([], [html.text("An unofficial PC port tracker.")]),
      ]),
      html.nav([], [
        html.div(
          [],
          list.map(
            [
              #("/", "what is this?"),
              #("/attempts", "attempts"),
              #("/community", "community"),
              #("/polls", "polls"),
            ],
            fn(link) {
              html.a(
                [
                  attribute.href(link.0),
                  attribute.aria_current(case link.0 == tab {
                    True -> "page"
                    False -> "false"
                  }),
                ],
                [html.text(link.1)],
              )
            },
          ),
        ),
        case user {
          Ok(user) ->
            html.form([attribute.method("post"), attribute.action("/logout")], [
              avatar(user.github_id),
              html.text(" " <> user.login <> " "),
              case user.notices {
                0 -> element.none()
                count ->
                  html.a(
                    [attribute.class("notice"), attribute.href("/notices")],
                    [html.text(plural(count, "notice"))],
                  )
              },
              html.text(" "),
              html.button([], [html.text("logout")]),
            ])
          Error(Nil) ->
            html.a([attribute.href("/login")], [html.text("login with GitHub")])
        },
      ]),
      html.main([], body),
    ]),
  ])
  |> element.to_document_string
  |> wisp.html_response(200)
}

pub fn problem(user: Result(User, Nil), message: String) -> Response {
  let res =
    frame("vitrack", "/community", user, [
      html.p([attribute.class("problem")], [html.text(message)]),
    ])
  Response(..res, status: 422)
}

pub fn row(
  post: Post,
  user: Result(User, Nil),
  back: List(#(String, String)),
) -> Element(a) {
  let id = int.to_string(post.id)
  let thread = "/post/" <> id
  html.li([attribute.id("p" <> id)], [
    case user {
      Ok(_) ->
        html.form(
          [
            attribute.class("votes"),
            attribute.method("post"),
            attribute.action(thread <> "/vote"),
          ],
          list.flatten([
            list.map(back, fn(field) {
              html.input([
                attribute.type_("hidden"),
                attribute.name(field.0),
                attribute.value(field.1),
              ])
            }),
            [
              html.button(
                [
                  attribute.name("value"),
                  attribute.value(case post.voted {
                    True -> "0"
                    False -> "1"
                  }),
                  attribute.title("upvote"),
                  attribute.classes([#("voted", post.voted)]),
                ],
                [html.text("▲")],
              ),
              html.text(int.to_string(post.score)),
            ],
          ]),
        )
      Error(Nil) ->
        html.div([attribute.class("votes")], [
          html.a(
            [attribute.href("/login?post=" <> id), attribute.title("upvote")],
            [html.text("▲")],
          ),
          html.text(int.to_string(post.score)),
        ])
    },
    html.div([], [
      case post.deleted {
        True -> html.text("[deleted]")
        False ->
          html.a([attribute.class("title"), attribute.href(thread)], [
            html.text(post.title),
          ])
      },
      html.p(
        [attribute.class("byline")],
        list.append(byline(post.github_id, "via " <> post.login, post.age), [
          html.text(" | "),
          html.a([attribute.href(thread)], [
            html.text(case post.comments {
              0 -> "no comments"
              count -> plural(count, "comment")
            }),
          ]),
          html.text(case post.pinned, post.locked {
            True, True -> " | pinned | closed"
            True, False -> " | pinned"
            False, True -> " | closed"
            False, False -> ""
          }),
        ]),
      ),
    ]),
  ])
}

pub fn byline(github_id: Int, name: String, age: Int) -> List(Element(a)) {
  [
    avatar(github_id),
    html.text(
      " "
      <> name
      <> " "
      <> case age {
        _ if age < 60 -> "just now"
        _ if age < 3600 -> plural(age / 60, "minute") <> " ago"
        _ if age < 86_400 -> plural(age / 3600, "hour") <> " ago"
        _ -> plural(age / 86_400, "day") <> " ago"
      },
    ),
  ]
}

pub fn text(body: String) -> List(Element(a)) {
  body
  |> string.replace("\r\n", "\n")
  |> string.split("\n\n")
  |> list.filter(fn(paragraph) { string.trim(paragraph) != "" })
  |> list.map(fn(paragraph) {
    string.trim(paragraph)
    |> string.split("\n")
    |> list.map(fn(line) {
      case string.contains(line, "://") {
        False -> [html.text(line)]
        True ->
          string.split(line, " ")
          |> list.map(fn(word) {
            case github.link(word) {
              True ->
                html.a(
                  [
                    attribute.href(word),
                    attribute.rel("ugc nofollow noreferrer"),
                  ],
                  [html.text(word)],
                )
              False -> html.text(word)
            }
          })
          |> list.intersperse(html.text(" "))
      }
    })
    |> list.intersperse([html.br([])])
    |> list.flatten
    |> html.p([], _)
  })
}

fn avatar(github_id: Int) -> Element(a) {
  html.img([
    attribute.src(case github_id {
      0 -> "/static/apple-touch-icon.png"
      _ ->
        "https://avatars.githubusercontent.com/u/"
        <> int.to_string(github_id)
        <> "?s=32"
    }),
    attribute.class("avatar"),
    attribute.alt(""),
    attribute.width(16),
    attribute.height(16),
    attribute.loading("lazy"),
  ])
}

fn plural(count: Int, word: String) -> String {
  case count {
    1 -> "1 " <> word
    _ -> int.to_string(count) <> " " <> word <> "s"
  }
}
