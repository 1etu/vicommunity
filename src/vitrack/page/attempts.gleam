import gleam/bool
import gleam/erlang/process
import gleam/http/response.{Response}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import pog.{type Connection}
import vitrack/attempt
import vitrack/page
import vitrack/typs/attempt_types.{type Attempt, Attempt}
import vitrack/typs/github_types.{type App}
import vitrack/typs/user_types.{type User, User}
import wisp.{type Request, type Response}

pub fn render(
  req: Request,
  db: Connection,
  app: App,
  user: Result(User, Nil),
) -> Response {
  let wanted = list.key_find(wisp.get_query(req), "gpu") |> result.unwrap("")
  let attempts =
    list.filter(attempt.all(db), fn(found) {
      case wanted {
        "amd" | "nvidia" -> found.gpu == wanted || found.gpu == "both"
        _ -> True
      }
    })
  list.each(attempts, renew(db, app, _))

  page.wide("attempts | vitrack", "/attempts", user, [
    views(user, case wanted {
      "amd" | "nvidia" -> wanted
      _ -> "all"
    }),
    html.table([attribute.class("list repos")], [
      heads([
        "#", "Name", "Description", "Owner", "GPU", "Status", "Idle", "Links",
      ]),
      ..list.index_map(attempts, fn(found, place) {
        let path = "/attempts/" <> found.slug
        html.tr([], [
          html.td([], [html.text(int.to_string(place + 1))]),
          html.td([], [html.a([attribute.href(path)], [html.text(found.name)])]),
          html.td(
            [attribute.class("clip"), attribute.title(found.description)],
            [html.text(found.description)],
          ),
          html.td([], [html.text(found.owner)]),
          html.td([], [html.text(card(found.gpu))]),
          html.td([], [status(found.status)]),
          html.td([], [age(found.idle)]),
          html.td(
            [],
            list.filter(["summary", "commits", "progress"], list.contains(
              tabs(found),
              _,
            ))
              |> list.map(fn(tab) {
                html.a([attribute.href(path <> "/" <> tab)], [html.text(tab)])
              }),
          ),
        ])
      })
    ]),
  ])
}

pub fn compare(db: Connection, app: App, user: Result(User, Nil)) -> Response {
  let ranked = attempt.all(db)
  list.each(ranked, renew(db, app, _))
  let furthest =
    list.first(ranked)
    |> result.map(fn(found) { found.status })
    |> result.unwrap("nothing")
  let leaders = list.filter(ranked, fn(found) { found.status == furthest })

  page.wide("compare | vitrack", "/attempts", user, [
    views(user, "compare"),
    html.p([], [
      html.text(
        "Furthest stage reached: "
        <> furthest
        <> ", by "
        <> string.join(list.map(leaders, fn(found) { found.name }), ", ")
        <> ". Order: stage, then commits in the last 7 days, then stars. The list uses the same order.",
      ),
    ]),
    html.pre(
      [attribute.class("chart")],
      list.flatten([
        [
          html.text(
            "                              nothing   boots     menus     in-game   playable"
            <> "\n"
            <> "                              |---------|---------|---------|---------|"
            <> "\n",
          ),
        ],
        list.index_map(ranked, fn(found, place) {
          let name = string.slice(found.name, 0, 24)
          [
            html.text(
              string.pad_start(int.to_string(place + 1), 3, " ") <> ". ",
            ),
            html.a([attribute.href("/attempts/" <> found.slug)], [
              html.text(name),
            ]),
            html.text(
              string.repeat(" ", 25 - string.length(name))
              <> string.pad_end(
                case attempt.stage(found.status) {
                  0 -> "x"
                  reached -> string.repeat("#", { reached - 1 } * 10 + 1)
                },
                43,
                " ",
              )
              <> found.status
              <> "\n",
            ),
          ]
        })
          |> list.flatten,
      ]),
    ),
    html.table([attribute.class("list tight")], [
      heads([
        "#", "Name", "Kind", "GPU", "Language", "Status", "Commits, 7 days",
        "Last commit", "Stars", "Forks", "Open issues",
      ]),
      ..list.index_map(ranked, fn(found, place) {
        html.tr(
          [],
          list.map(
            [
              html.text(int.to_string(place + 1)),
              html.a([attribute.href("/attempts/" <> found.slug)], [
                html.text(found.name),
              ]),
              html.text(found.kind),
              html.text(card(found.gpu)),
              html.text(found.language),
              status(found.status),
              html.text(case found.recent >= 100 {
                True -> "100+"
                False -> int.to_string(found.recent)
              }),
              age(found.idle),
              html.text(int.to_string(found.stars)),
              html.text(int.to_string(found.forks)),
              html.text(int.to_string(found.issues)),
            ],
            fn(cell) { html.td([], [cell]) },
          ),
        )
      })
    ]),
  ])
}

fn views(user: Result(User, Nil), current: String) -> Element(a) {
  html.nav(
    [attribute.class("subtabs")],
    list.map(
      list.flatten([
        [
          #("/attempts", "all"),
          #("/attempts?gpu=amd", "amd"),
          #("/attempts?gpu=nvidia", "nvidia"),
          #("/attempts/compare", "compare"),
        ],
        case user {
          Ok(User(admin: True, ..)) -> [#("/attempts/new", "new attempt")]
          _ -> []
        },
      ]),
      fn(link) {
        html.a(
          [
            attribute.href(link.0),
            attribute.aria_current(case link.1 == current {
              True -> "page"
              False -> "false"
            }),
          ],
          [html.text(link.1)],
        )
      },
    ),
  )
}

fn card(gpu: String) -> String {
  case gpu {
    "unknown" -> ""
    _ -> gpu
  }
}

pub fn show(
  db: Connection,
  app: App,
  user: Result(User, Nil),
  slug: String,
  tab: String,
) -> Response {
  use found <- visit(db, slug)
  renew(db, app, found)
  let tab = case tab {
    "" -> "summary"
    _ -> tab
  }
  let path = "/attempts/" <> slug
  use <- bool.guard(!list.contains(tabs(found), tab), wisp.not_found())

  frame(found, tab, user, case tab {
    "about" -> [
      case attempt.readme(db, found.id) {
        "" -> html.p([], [html.text("This repository has no README.")])
        readme -> html.pre([], [html.text(readme)])
      },
    ]
    "summary" -> {
      let history = attempt.history(db, found.id)
      let commits = attempt.commits(db, found.id)
      let sources =
        list.flatten([
          case found.repo {
            "" -> []
            repo -> ["https://github.com/" <> repo <> ".git"]
          },
          case found.mirrors {
            "" -> []
            mirrors -> string.split(mirrors, "\n")
          },
        ])
      [
        html.table(
          [attribute.class("list")],
          list.flatten([
            [heads(["Status", "Note", "Age"])],
            list.map(list.take(history, 10), step),
            more(history, path <> "/progress"),
            case commits {
              [] -> []
              _ ->
                list.flatten([
                  [gap(), heads(["Age", "Commit message", "Author"])],
                  list.map(list.take(commits, 10), log(path, _)),
                  more(commits, path <> "/commits"),
                ])
            },
            case sources {
              [] -> []
              _ -> [
                gap(),
                heads(["Clone"]),
                ..list.map(sources, fn(line) {
                  let #(label, url) = attempt.mirror(line)
                  html.tr([], [
                    html.td([attribute.colspan(3)], [
                      html.a([attribute.href(url)], [html.text(label)]),
                    ]),
                  ])
                })
              ]
            },
          ]),
        ),
      ]
    }
    "commits" -> [
      html.table([attribute.class("list")], [
        heads(["Age", "Commit message", "Author"]),
        ..list.map(attempt.commits(db, found.id), log(path, _))
      ]),
    ]
    "mirrors" -> [
      html.table(
        [attribute.class("list")],
        list.map(string.split(found.mirrors, "\n"), fn(line) {
          let #(label, url) = attempt.mirror(line)
          html.tr([], [
            html.td([], [
              html.a([attribute.href(url), attribute.rel("noreferrer")], [
                html.text(label),
              ]),
            ]),
          ])
        }),
      ),
    ]
    _ -> [
      case user {
        Ok(User(admin: True, ..)) ->
          html.form(
            [
              attribute.method("post"),
              attribute.action("/attempts/" <> slug <> "/progress"),
            ],
            [
              choose("status", attempt.statuses, found.status),
              html.text(" "),
              html.input([
                attribute.name("note"),
                attribute.maxlength(500),
                attribute.placeholder("what changed"),
                attribute.aria_label("note"),
              ]),
              html.text(" "),
              html.input([attribute.type_("submit"), attribute.value("add")]),
            ],
          )
        _ -> element.none()
      },
      html.table([attribute.class("list")], [
        heads(["Status", "Note", "Age"]),
        ..list.map(attempt.history(db, found.id), step)
      ]),
    ]
  })
}

pub fn commit(
  db: Connection,
  app: App,
  user: Result(User, Nil),
  slug: String,
  sha: String,
) -> Response {
  use found <- visit(db, slug)
  case attempt.commit(db, app, found, sha) {
    Error(Nil) -> wisp.not_found()
    Ok(commit) ->
      frame(found, "commits", user, [
        html.table([], [
          html.tr([], [
            html.td([], [html.text("author")]),
            html.td([], [html.text(commit.author)]),
          ]),
          html.tr([], [
            html.td([], [html.text("age")]),
            html.td([], [age(commit.age)]),
          ]),
          html.tr([], [
            html.td([], [html.text("commit")]),
            html.td([], [
              html.a(
                [
                  attribute.href(
                    "https://github.com/" <> found.repo <> "/commit/" <> sha,
                  ),
                  attribute.rel("noreferrer"),
                ],
                [html.text(sha)],
              ),
            ]),
          ]),
        ]),
        html.h3([], [html.text(subject(commit.message))]),
        html.pre([], [
          html.text(
            string.split_once(commit.message, "\n")
            |> result.map(fn(parts) { string.trim(parts.1) })
            |> result.unwrap(""),
          ),
        ]),
        html.pre(
          [attribute.class("diff")],
          list.map(string.split(commit.diff, "\n"), fn(line) {
            html.span(
              [
                attribute.class(case line {
                  "diff " <> _ | "index " <> _ | "--- " <> _ | "+++ " <> _ ->
                    "head"
                  "@@" <> _ -> "hunk"
                  "+" <> _ -> "add"
                  "-" <> _ -> "del"
                  _ -> ""
                }),
              ],
              [html.text(line <> "\n")],
            )
          }),
        ),
      ])
  }
}

pub fn form(user: User) -> Response {
  use <- bool.guard(!user.admin, wisp.not_found())
  page.wide("new attempt | vitrack", "/attempts", Ok(user), [
    fields("/attempts", "", blank()),
  ])
}

pub fn create(req: Request, db: Connection, app: App, user: User) -> Response {
  use <- bool.guard(!user.admin, wisp.not_found())
  use form <- wisp.require_form(req)
  let entered = fill(blank(), form)
  case attempt.save(db, app, entered) {
    Ok(slug) -> wisp.redirect("/attempts/" <> slug)
    Error(problem) -> {
      let res =
        page.wide("new attempt | vitrack", "/attempts", Ok(user), [
          fields("/attempts", problem, entered),
        ])
      Response(..res, status: 422)
    }
  }
}

pub fn edit(db: Connection, user: User, slug: String) -> Response {
  use <- bool.guard(!user.admin, wisp.not_found())
  use found <- visit(db, slug)
  frame(found, "edit", Ok(user), editor(found, ""))
}

pub fn update(
  req: Request,
  db: Connection,
  app: App,
  user: User,
  slug: String,
) -> Response {
  use <- bool.guard(!user.admin, wisp.not_found())
  use form <- wisp.require_form(req)
  use found <- visit(db, slug)
  let entered = fill(found, form)
  case attempt.save(db, app, entered) {
    Ok(_) -> wisp.redirect("/attempts/" <> slug)
    Error(problem) -> {
      let res = frame(found, "edit", Ok(user), editor(entered, problem))
      Response(..res, status: 422)
    }
  }
}

pub fn record(
  req: Request,
  db: Connection,
  user: User,
  slug: String,
) -> Response {
  use <- bool.guard(!user.admin, wisp.not_found())
  use form <- wisp.require_form(req)
  use found <- visit(db, slug)
  let field = fn(name) { list.key_find(form.values, name) |> result.unwrap("") }
  case attempt.record(db, found.id, field("status"), field("note")) {
    Ok(Nil) -> wisp.redirect("/attempts/" <> slug <> "/progress")
    Error(problem) -> page.problem(Ok(user), problem)
  }
}

pub fn delete(db: Connection, user: User, slug: String) -> Response {
  use <- bool.guard(!user.admin, wisp.not_found())
  use found <- visit(db, slug)
  attempt.delete(db, found.id)
  wisp.redirect("/attempts")
}

fn visit(
  db: Connection,
  slug: String,
  next: fn(Attempt) -> Response,
) -> Response {
  case attempt.find(db, slug) {
    Ok(found) -> next(found)
    Error(Nil) -> wisp.not_found()
  }
}

fn renew(db: Connection, app: App, found: Attempt) -> Nil {
  case found.stale && attempt.claim(db, found.id) {
    True -> {
      process.spawn_unlinked(fn() { attempt.refresh(db, app, found) })
      Nil
    }
    False -> Nil
  }
}

fn tabs(found: Attempt) -> List(String) {
  list.flatten([
    case found.repo {
      "" -> ["summary"]
      _ -> ["about", "summary", "commits"]
    },
    ["progress"],
    case found.mirrors {
      "" -> []
      _ -> ["mirrors"]
    },
  ])
}

fn frame(
  found: Attempt,
  tab: String,
  user: Result(User, Nil),
  body: List(Element(a)),
) -> Response {
  let path = "/attempts/" <> found.slug
  let link = fn(href, label) {
    html.a(
      [
        attribute.href(href),
        attribute.aria_current(case label == tab {
          True -> "page"
          False -> "false"
        }),
      ],
      [html.text(label)],
    )
  }

  page.wide(found.name <> " | vitrack", "/attempts", user, [
    html.h2([], [
      html.span([], [
        html.a([attribute.href("/attempts")], [html.text("index")]),
        html.text(" : " <> found.name),
      ]),
      html.small([], [status(found.status), html.text(" " <> found.owner)]),
    ]),
    html.p([attribute.class("byline")], [html.text(found.description)]),
    html.nav(
      [attribute.class("tabs")],
      list.flatten([
        list.map(tabs(found), fn(name) { link(path <> "/" <> name, name) }),
        case found.discord {
          "" -> []
          discord -> [link(discord, "discord")]
        },
        case user {
          Ok(User(admin: True, ..)) -> [link(path <> "/edit", "edit")]
          _ -> []
        },
      ]),
    ),
    ..body
  ])
}

fn heads(titles: List(String)) -> Element(a) {
  html.tr(
    [attribute.class("plain")],
    list.map(titles, fn(title) { html.th([], [html.text(title)]) }),
  )
}

fn gap() -> Element(a) {
  html.tr([attribute.class("plain")], [
    html.td([attribute.colspan(3)], [html.text("\u{a0}")]),
  ])
}

fn more(rows: List(b), path: String) -> List(Element(a)) {
  case list.length(rows) > 10 {
    True -> [
      html.tr([attribute.class("plain")], [
        html.td([attribute.colspan(3)], [
          html.a([attribute.href(path)], [html.text("[...]")]),
        ]),
      ]),
    ]
    False -> []
  }
}

fn step(entry: attempt_types.Entry) -> Element(a) {
  html.tr([], [
    html.td([], [status(entry.status)]),
    html.td([], [html.text(entry.note)]),
    html.td([], [age(entry.age)]),
  ])
}

fn log(path: String, commit: attempt_types.Commit) -> Element(a) {
  html.tr([], [
    html.td([], [age(commit.age)]),
    html.td([], [
      html.a([attribute.href(path <> "/commits/" <> commit.sha)], [
        html.text(subject(commit.message)),
      ]),
    ]),
    html.td([], [html.text(commit.author)]),
  ])
}

fn editor(found: Attempt, problem: String) -> List(Element(a)) {
  [
    fields("/attempts/" <> found.slug, problem, found),
    html.form(
      [
        attribute.method("post"),
        attribute.action("/attempts/" <> found.slug <> "/delete"),
      ],
      [html.button([], [html.text("delete this attempt")])],
    ),
  ]
}

fn fields(action: String, problem: String, found: Attempt) -> Element(a) {
  let input = fn(name, value, hint) {
    [
      html.label([attribute.for(name)], [html.text(name)]),
      html.input([
        attribute.id(name),
        attribute.name(name),
        attribute.value(value),
        attribute.placeholder(hint),
      ]),
    ]
  }

  html.div([], [
    case problem {
      "" -> element.none()
      _ -> html.p([attribute.class("problem")], [html.text(problem)])
    },
    html.form(
      [
        attribute.class("submit"),
        attribute.method("post"),
        attribute.action(action),
      ],
      list.flatten([
        input("name", found.name, ""),
        [
          html.label([attribute.for("kind")], [html.text("kind")]),
          choose("kind", attempt.kinds, found.kind),
          html.label([attribute.for("gpu")], [html.text("gpu")]),
          choose("gpu", attempt.gpus, found.gpu),
        ],
        input("description", found.description, ""),
        input("owner", found.owner, ""),
        input("repo", found.repo, "owner/name on GitHub, optional"),
        input("discord", found.discord, "https://discord.gg/..., optional"),
        [
          html.label([attribute.for("mirrors")], [html.text("mirrors")]),
          html.textarea(
            [
              attribute.id("mirrors"),
              attribute.name("mirrors"),
              attribute.rows(5),
              attribute.placeholder(
                "one per line: a label, then a magnet, https or git address",
              ),
            ],
            found.mirrors,
          ),
          html.span([], []),
          html.input([attribute.type_("submit"), attribute.value("save")]),
        ],
      ]),
    ),
  ])
}

fn choose(name: String, options: List(String), chosen: String) -> Element(a) {
  html.select(
    [attribute.id(name), attribute.name(name)],
    list.map(options, fn(option) {
      html.option(
        [attribute.value(option), attribute.selected(option == chosen)],
        option,
      )
    }),
  )
}

fn blank() -> Attempt {
  Attempt(
    id: 0,
    slug: "",
    name: "",
    kind: "emulator",
    description: "",
    owner: "",
    status: "nothing",
    repo: "",
    discord: "",
    mirrors: "",
    idle: -1,
    stale: False,
    stars: 0,
    forks: 0,
    issues: 0,
    language: "",
    recent: 0,
    gpu: "unknown",
  )
}

fn fill(found: Attempt, form: wisp.FormData) -> Attempt {
  let field = fn(name) { list.key_find(form.values, name) |> result.unwrap("") }
  Attempt(
    ..found,
    name: field("name"),
    kind: field("kind"),
    gpu: field("gpu"),
    description: field("description"),
    owner: field("owner"),
    repo: field("repo"),
    discord: string.trim(field("discord")),
    mirrors: field("mirrors"),
  )
}

fn subject(message: String) -> String {
  string.split_once(message, "\n")
  |> result.map(fn(parts) { parts.0 })
  |> result.unwrap(message)
}

fn status(label: String) -> Element(a) {
  html.span([attribute.class("status " <> label)], [html.text(label)])
}

fn age(seconds: Int) -> Element(a) {
  let #(text, class) = case seconds {
    _ if seconds < 0 -> #("", "")
    _ if seconds < 7200 -> #(int.to_string(seconds / 60) <> " min.", "mins")
    _ if seconds < 172_800 -> #(
      int.to_string(seconds / 3600) <> " hours",
      "hours",
    )
    _ if seconds < 1_209_600 -> #(
      int.to_string(seconds / 86_400) <> " days",
      "days",
    )
    _ if seconds < 5_184_000 -> #(
      int.to_string(seconds / 604_800) <> " weeks",
      "weeks",
    )
    _ if seconds < 63_072_000 -> #(
      int.to_string(seconds / 2_592_000) <> " months",
      "months",
    )
    _ -> #(int.to_string(seconds / 31_536_000) <> " years", "years")
  }
  html.span([attribute.class(class)], [html.text(text)])
}
