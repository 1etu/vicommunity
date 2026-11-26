import gleam/bool
import gleam/http/response.{Response}
import gleam/int
import gleam/list
import gleam/result
import lustre/attribute
import lustre/element
import lustre/element/html
import pog.{type Connection}
import vitrack/notice
import vitrack/page
import vitrack/photo
import vitrack/post
import vitrack/typs/user_types.{type User}
import wisp.{type Request, type Response}

pub fn form(user: User) -> Response {
  show(user, "", "", "")
}

fn show(user: User, problem: String, title: String, text: String) -> Response {
  let res =
    page.frame("submit | vitrack", "/community", Ok(user), [
      case problem {
        "" -> element.none()
        _ -> html.p([attribute.class("problem")], [html.text(problem)])
      },
      html.form(
        [
          attribute.class("submit"),
          attribute.method("post"),
          attribute.action("/submit"),
          attribute.enctype("multipart/form-data"),
        ],
        list.flatten([
          [
            html.label([attribute.for("title")], [html.text("title")]),
            html.input([
              attribute.id("title"),
              attribute.name("title"),
              attribute.value(title),
              attribute.maxlength(100),
              attribute.required(True),
            ]),
            html.label([attribute.for("text")], [html.text("text")]),
            html.textarea(
              [attribute.id("text"), attribute.name("text"), attribute.rows(8)],
              text,
            ),
          ],
          list.flat_map([1, 2, 3], fn(number) {
            let id = "photo" <> int.to_string(number)
            [
              html.label([attribute.for(id)], [html.text("photo")]),
              html.input([
                attribute.id(id),
                attribute.name("photo"),
                attribute.type_("file"),
                attribute.accept(["image/jpeg", "image/png", "image/webp"]),
              ]),
            ]
          }),
          [
            html.span([], []),
            html.input([attribute.type_("submit"), attribute.value("submit")]),
          ],
        ]),
      ),
      html.p([], [
        html.text(
          "Text and photos are optional. Photos must be JPEG, PNG or WebP, at most 8 MB each. Only links to GitHub are allowed; a post with any other link is removed.",
        ),
      ]),
    ])
  case problem {
    "" -> res
    _ -> Response(..res, status: 422)
  }
}

pub fn create(req: Request, db: Connection, user: User) -> Response {
  use form <- wisp.require_form(req)
  let field = fn(name) { list.key_find(form.values, name) |> result.unwrap("") }
  let title = field("title")
  let text = field("text")
  let again = show(user, _, title, text)
  let uploads = list.filter(form.files, fn(file) { { file.1 }.file_name != "" })
  use <- bool.lazy_guard(list.length(uploads) > 3, fn() {
    again("A post can have at most 3 photos.")
  })
  use <- bool.lazy_guard(
    notice.removes(db, user.id, title <> "\n\n" <> text),
    fn() { wisp.redirect("/notices") },
  )

  case post.allowed(db, user.id, title, text) {
    Error(problem) -> again(problem)
    Ok(Nil) -> {
      let converted =
        list.map(uploads, fn(file) {
          photo.convert({ file.1 }.path, wisp.random_string(16))
        })
      let photos = result.values(converted)
      let files = list.map(photos, fn(photo) { photo.file })
      case list.length(photos) == list.length(converted) {
        False -> {
          photo.discard(files)
          again("Photos must be JPEG, PNG or WebP, at most 8 MB each.")
        }
        True ->
          case post.create(db, user.id, title, text) {
            Ok(id) -> {
              photo.save(db, id, photos)
              wisp.redirect("/post/" <> int.to_string(id))
            }
            Error(problem) -> {
              photo.discard(files)
              again(problem)
            }
          }
      }
    }
  }
}
