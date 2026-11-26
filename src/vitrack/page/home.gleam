import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import vitrack/page
import vitrack/typs/user_types.{type User}
import wisp.{type Response}

pub fn render(user: Result(User, Nil)) -> Response {
  page.frame("vitrack", "/", user, [
    html.article([], [contents(), ..list.index_map(sections(), section)]),
  ])
}

fn contents() -> Element(a) {
  html.nav([], [
    html.h2([], [html.text("Contents")]),
    html.ol(
      [],
      list.map(sections(), fn(entry) {
        let #(id, title, _) = entry
        html.li([], [html.a([attribute.href("#" <> id)], [html.text(title)])])
      }),
    ),
  ])
}

fn section(
  entry: #(String, String, List(Element(a))),
  index: Int,
) -> Element(a) {
  let #(id, title, body) = entry
  html.section([attribute.id(id)], [
    html.h2([], [
      html.text(int.to_string(index + 1) <> ". " <> title),
      html.a([attribute.href("#top")], [html.text("top")]),
    ]),
    ..body
  ])
}

fn sections() -> List(#(String, String, List(Element(a)))) {
  [
    #("description", "Description", [
      p(
        "Grand Theft Auto VI came out on 19 November 2026 for PlayStation 5 and Xbox Series X|S. No PC version has been announced.",
      ),
      p(
        "Rockstar's earlier games did reach PC, but late. Grand Theft Auto V took nineteen months. Red Dead Redemption 2 took a year. The first Red Dead Redemption took fourteen years.",
      ),
      p(
        "People are trying anyway. Some write emulators, some recompile the game, some build compatibility layers, and some try ideas that do not have a name yet. Most attempts will fail. A few will get further than anyone expected. All of them are worth writing down.",
      ),
      p(
        "This site writes them down. Each attempt has a page with what it is, who works on it, how far it has got, and a dated history of every change in status. Nothing is removed when an attempt is abandoned. A dead end is also information.",
      ),
    ]),
    #("kinds", "Kinds of attempt", [
      p(
        "Both consoles use the same kind of processor as a PC. The hard part is everything around it: the system software, the graphics chip, the storage. Most attempts take one of three routes.",
      ),
      html.dl([], [
        html.dt([], [html.text("Emulator")]),
        html.dd([], [
          html.text(
            "Imitates the whole console in software, so the unchanged game runs as if it were on a PlayStation or an Xbox. The most faithful route and the slowest to build.",
          ),
        ]),
        html.dt([], [html.text("Recompiler")]),
        html.dd([], [
          html.text(
            "Converts the game's program into one a PC can run, before the game starts.",
          ),
        ]),
        html.dt([], [html.text("Compatibility layer")]),
        html.dd([], [
          html.text(
            "Runs the game's own code and answers its calls to the console with PC equivalents. Wine does the same for Windows programs on Linux.",
          ),
        ]),
      ]),
      p(
        "Streaming from a console or a cloud service, recreations of the map inside other games, and videos with nothing behind them are not tracked.",
      ),
    ]),
    #("status", "Status", [
      p(
        "Every attempt carries one label. It shows the furthest point the attempt has reached.",
      ),
      html.table(
        [],
        list.map(
          [
            #("nothing", "Announced. No public result yet."),
            #("boots", "The game starts, then stops."),
            #("menus", "Reaches the menus. Does not reach the world."),
            #("in-game", "Reaches the world. Not yet playable."),
            #("playable", "Can be played from start to finish."),
            #(
              "abandoned",
              "Work has stopped. The last label stays in the history.",
            ),
          ],
          fn(row) {
            let #(label, meaning) = row
            html.tr([], [
              html.td([], [
                html.span([attribute.class("status " <> label)], [
                  html.text(label),
                ]),
              ]),
              html.td([], [html.text(meaning)]),
            ])
          },
        ),
      ),
      p(
        "A label changes only when there is something others can check: source code, a build of the tool, a log or a write-up. A video is a claim. Claims are marked unverified until someone else reproduces them.",
      ),
    ]),
    #("not", "What this site is not", [
      p(
        "It is not a download site. There are no game files here, no keys, no leaked builds and no links to any of them. Posts that contain them are deleted.",
      ),
      p(
        "It is not affiliated with Rockstar Games or Take-Two Interactive. Grand Theft Auto and its logos are trademarks of Take-Two Interactive Software.",
      ),
      p(
        "It is not a rumour site. Release date guesses belong elsewhere. If an official PC version is announced, it will be reported once, with a source.",
      ),
    ]),
    #("community", "Community", [
      p(
        "Anyone may send a link, a correction or a question. Write as you would to a colleague: say what you tried and what happened. Corrections are applied to the tracker with credit.",
      ),
    ]),
    #("end-of-life", "End of life", [
      p(
        "On the day an official PC version ships, the tracker is frozen. The site stays online as an archive of what people managed to do without one.",
      ),
    ]),
    #("bugs", "Bugs", [
      p(
        "The site is run by one person. Entries may be late, incomplete or wrong. Reports are read.",
      ),
    ]),
  ]
}

fn p(text: String) -> Element(a) {
  html.p([], [html.text(text)])
}
