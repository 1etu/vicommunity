import gleam/erlang/application
import gleam/list
import gleam/string
import simplifile

const markup = [
  "<script", "</script", "<iframe", "<img", "<svg", "<object", "<embed",
  "<style", "<link", "<meta", "<form", "<input", "<body", "<html", "<a ",
  "javascript:", "onerror=", "onload=", "onclick=", "onmouseover=",
]

const masks = [
  #("0", "o"),
  #("1", "i"),
  #("3", "e"),
  #("4", "a"),
  #("5", "s"),
  #("7", "t"),
  #("@", "a"),
  #("$", "s"),
  #("!", "i"),
]

pub fn check(text: String) -> Result(Nil, String) {
  let lower = string.lowercase(text)
  let assert Ok(priv) = application.priv_directory("vitrack")
  let assert Ok(blocked) = simplifile.read(priv <> "/blocked.txt")
  let plain = words(lower)
  let unmasked =
    words(
      list.fold(masks, lower, fn(text, mask) {
        string.replace(text, mask.0, mask.1)
      }),
    )

  case list.any(markup, string.contains(lower, _)) {
    True -> Error("Posts cannot contain HTML or script.")
    False ->
      case
        string.split(blocked, "\n")
        |> list.any(fn(entry) {
          entry != ""
          && {
            string.contains(plain, " " <> entry <> " ")
            || string.contains(unmasked, " " <> entry <> " ")
          }
        })
      {
        True -> Error("Please leave out the swearing and slurs.")
        False -> Ok(Nil)
      }
  }
}

fn words(text: String) -> String {
  let kept =
    string.to_graphemes(text)
    |> list.map(fn(letter) {
      case string.contains("abcdefghijklmnopqrstuvwxyz0123456789", letter) {
        True -> letter
        False -> " "
      }
    })
    |> string.concat
    |> string.split(" ")
    |> list.filter(fn(word) { word != "" })
    |> string.join(" ")
  " " <> kept <> " "
}
