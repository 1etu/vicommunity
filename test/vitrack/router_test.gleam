import envoy
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/list
import gleam/string
import pog.{type Connection}
import simplifile
import vitrack/comment
import vitrack/github
import vitrack/language
import vitrack/poll
import vitrack/post
import vitrack/router
import vitrack/typs/github_types.{App}
import vitrack/typs/poll_types
import vitrack/user
import wisp.{type Response}
import wisp/simulate.{FileUpload}

fn open() -> Connection {
  let assert Ok(url) = envoy.get("DATABASE_URL")
  let assert Ok(config) = pog.url_config(process.new_name("test"), url)
  let assert Ok(pool) = pog.start(pog.pool_size(config, 2))
  pool.data
}

fn join(pool: Connection) -> String {
  let member = user.save(pool, int.random(1_000_000_000), "tester")
  let token = wisp.random_string(64)
  user.login(pool, member.id, token)
  token
}

fn get(pool: Connection, path: String, token: String) -> Response {
  simulate.browser_request(http.Get, path)
  |> simulate.cookie("session", token, wisp.PlainText)
  |> router.handle(pool, App("id", "secret"))
}

fn send(
  pool: Connection,
  path: String,
  token: String,
  fields: List(#(String, String)),
) -> Response {
  simulate.browser_request(http.Post, path)
  |> simulate.cookie("session", token, wisp.PlainText)
  |> simulate.form_body(fields)
  |> router.handle(pool, App("id", "secret"))
}

fn submit(pool: Connection, token: String, title: String) -> Int {
  let res = send(pool, "/submit", token, [#("title", title), #("text", "")])
  let assert Ok("/post/" <> id) = list.key_find(res.headers, "location")
  let assert Ok(id) = int.parse(id)
  id
}

pub fn pages_test() {
  let pool = open()

  assert get(pool, "/", "").status == 200
  assert get(pool, "/attempts", "").status == 200
  assert get(pool, "/community", "").status == 200
  assert get(pool, "/community/new", "").status == 200
  assert get(pool, "/nope", "").status == 404
  assert list.key_find(get(pool, "/", "").headers, "content-security-policy")
    != Error(Nil)
}

pub fn login_needed_test() {
  let pool = open()

  assert get(pool, "/submit", "").status == 303
  let res = send(pool, "/submit", "", [#("title", "nobody")])
  assert list.key_find(res.headers, "location") == Ok("/login")
  let res = send(pool, "/post/1/vote", "", [#("value", "1")])
  assert list.key_find(res.headers, "location") == Ok("/login")
}

pub fn submit_test() {
  let pool = open()
  let title = "post " <> wisp.random_string(8)
  let id = submit(pool, join(pool), title)

  let newest = simulate.read_body(get(pool, "/community/new", ""))
  assert string.contains(newest, title)
  let thread = get(pool, "/post/" <> int.to_string(id), "")
  assert string.contains(simulate.read_body(thread), title)
}

pub fn vote_test() {
  let pool = open()
  let voter = join(pool)
  let id = submit(pool, join(pool), "votes")
  let path = "/post/" <> int.to_string(id) <> "/vote"
  let score = fn() {
    let assert Ok(found) = post.find(pool, 0, id)
    found.score
  }

  assert score() == 1
  let _ = send(pool, path, voter, [#("value", "1")])
  let _ = send(pool, path, voter, [#("value", "1")])
  assert score() == 2
  let _ = send(pool, path, voter, [#("value", "0")])
  assert score() == 1
  assert send(pool, path, voter, [#("value", "1000")]).status == 400
  assert score() == 1
}

pub fn comment_test() {
  let pool = open()
  let author = join(pool)
  let other = join(pool)
  let id = submit(pool, author, "comments")
  let thread = "/post/" <> int.to_string(id)

  let res = send(pool, thread <> "/comment", author, [#("text", "first words")])
  assert res.status == 303
  let assert [first] = comment.tree(pool, 0, id)
  let reply = "/reply/" <> int.to_string(first.id)
  assert send(pool, reply, other, [#("text", "second words")]).status == 303

  let body = simulate.read_body(get(pool, thread, ""))
  assert string.contains(body, "first words")
  assert string.contains(body, "second words")

  let vote = "/comment/" <> int.to_string(first.id) <> "/vote"
  let _ = send(pool, vote, other, [#("value", "-1")])
  let assert [first] = comment.tree(pool, 0, id)
  assert first.score == 0
  let assert [second] = first.replies
  assert second.depth == 1
  let assert Ok(found) = post.find(pool, 0, id)
  assert found.comments == 2
}

pub fn refused_test() {
  let pool = open()
  let token = join(pool)
  let upload = fn(count) {
    simulate.browser_request(http.Post, "/submit")
    |> simulate.cookie("session", token, wisp.PlainText)
    |> simulate.multipart_body(
      [#("title", "photos"), #("text", "")],
      list.repeat(
        #(
          "photo",
          FileUpload("shot.png", "image/png", <<"not a picture":utf8>>),
        ),
        count,
      ),
    )
    |> router.handle(pool, App("id", "secret"))
  }

  assert send(pool, "/submit", token, [#("title", ""), #("text", "")]).status
    == 422
  assert upload(1).status == 422
  assert upload(4).status == 422
}

pub fn foreign_site_test() {
  let pool = open()
  let res =
    simulate.browser_request(http.Post, "/submit")
    |> simulate.header("origin", "https://elsewhere.example")
    |> simulate.cookie("session", join(pool), wisp.PlainText)
    |> simulate.form_body([#("title", "forged"), #("text", "")])
    |> router.handle(pool, App("id", "secret"))

  assert res.status == 400
}

pub fn delete_test() {
  let pool = open()
  let author = join(pool)
  let id = submit(pool, author, "mine")
  let path = "/post/" <> int.to_string(id) <> "/delete"

  assert send(pool, path, join(pool), []).status == 404
  let assert Ok(found) = post.find(pool, 0, id)
  assert !found.deleted
  assert send(pool, path, author, []).status == 303
  let assert Ok(found) = post.find(pool, 0, id)
  assert found.deleted
}

pub fn logout_test() {
  let pool = open()
  let token = join(pool)

  assert get(pool, "/submit", token).status == 200
  assert send(pool, "/logout", token, []).status == 303
  assert get(pool, "/submit", token).status == 303
}

pub fn links_test() {
  let pool = open()
  let token = join(pool)
  let title = "links " <> wisp.random_string(8)
  let post = fn(text) {
    send(pool, "/submit", token, [#("title", title), #("text", text)])
  }

  let res = post("read this https://elsewhere.example/page")
  assert list.key_find(res.headers, "location") == Ok("/notices")
  let newest = simulate.read_body(get(pool, "/community/new", ""))
  assert !string.contains(newest, title)
  let notices = simulate.read_body(get(pool, "/notices", token))
  assert string.contains(notices, "Your message was deleted")
  assert string.contains(notices, "elsewhere.example/page")

  let res = post("source is at https://github.com/example/attempt")
  let assert Ok("/post/" <> id) = list.key_find(res.headers, "location")
  let thread = simulate.read_body(get(pool, "/post/" <> id, ""))
  assert string.contains(thread, "href=\"https://github.com/example/attempt\"")
}

pub fn too_fast_test() {
  let pool = open()
  let token = join(pool)
  let id = submit(pool, token, "first")
  let comment = "/post/" <> int.to_string(id) <> "/comment"

  let res = send(pool, "/submit", token, [#("title", "second"), #("text", "")])
  assert res.status == 422
  assert string.contains(simulate.read_body(res), "posting too fast")
  assert send(pool, comment, token, [#("text", "one")]).status == 303
  assert send(pool, comment, token, [#("text", "two")]).status == 422
}

pub fn injection_test() {
  let pool = open()
  let token = join(pool)
  let title = "</title><b>bold</b> & \"quoted\""
  let text =
    "<b>bold</b> </textarea><i>slanted</i> https://github.com/example/\"onfocus=\"alert(4)"
  let safe = fn(body) {
    !string.contains(body, "<b>")
    && !string.contains(body, "<i>")
    && !string.contains(body, "\"onfocus=")
  }

  let res = send(pool, "/submit", token, [#("title", title), #("text", text)])
  let assert Ok("/post/" <> id) = list.key_find(res.headers, "location")
  let _ = send(pool, "/post/" <> id <> "/comment", token, [#("text", text)])
  let thread = simulate.read_body(get(pool, "/post/" <> id, token))
  assert string.contains(thread, "&lt;b&gt;bold")
  assert safe(thread)
  assert safe(simulate.read_body(get(pool, "/community/new", token)))

  let again = send(pool, "/submit", token, [#("title", title), #("text", text)])
  assert again.status == 422
  assert safe(simulate.read_body(again))

  let other = join(pool)
  let removed = text <> " http://elsewhere.example/<b>"
  let _ = send(pool, "/post/" <> id <> "/comment", other, [#("text", removed)])
  assert safe(simulate.read_body(get(pool, "/notices", other)))
}

pub fn language_test() {
  let pool = open()
  let token = join(pool)
  let assert Ok(priv) = wisp.priv_directory("vitrack")
  let assert Ok(blocked) = simplifile.read(priv <> "/blocked.txt")
  let assert [word, ..] = string.split(blocked, "\n")
  let refused = fn(title, text) {
    let res = send(pool, "/submit", token, [#("title", title), #("text", text)])
    #(res.status, simulate.read_body(res))
  }

  let #(status, body) = refused("a title", "<script>alert(1)</script>")
  assert status == 422
  assert string.contains(body, "cannot contain HTML or script")
  assert !string.contains(body, "<script>")
  let #(status, body) = refused("Something " <> string.uppercase(word), "")
  assert status == 422
  assert string.contains(body, "leave out the swearing")
  assert language.check("An assessment of the classic Vec<u8> case") == Ok(Nil)
  assert language.check("a <= b and b < c") == Ok(Nil)
  assert language.check("see <img src=x onerror=alert(1)>") != Ok(Nil)
}

pub fn attempts_test() {
  let pool = open()
  let visitor = join(pool)
  let admin = wisp.random_string(64)
  let member = user.save(pool, int.random(1_000_000_000), "admin")
  user.login(pool, member.id, admin)
  let assert Ok(_) =
    pog.query("update users set admin = true where id = $1")
    |> pog.parameter(pog.int(member.id))
    |> pog.execute(pool)
  let name = "Try " <> string.lowercase(wisp.random_string(8))
  let fields = [
    #("name", name),
    #("kind", "emulator"),
    #("gpu", "nvidia"),
    #("description", "<b>first of its kind</b>"),
    #("owner", "someone"),
    #("repo", ""),
    #("discord", "https://discord.gg/example"),
    #("mirrors", "source archive magnet:?xt=urn:btih:abc"),
  ]

  assert send(pool, "/attempts", visitor, fields).status == 404
  assert get(pool, "/attempts/new", visitor).status == 404
  let res = send(pool, "/attempts", admin, fields)
  let assert Ok("/attempts/" <> slug) = list.key_find(res.headers, "location")
  let path = "/attempts/" <> slug

  let index = simulate.read_body(get(pool, "/attempts", ""))
  assert string.contains(index, name)
  assert string.contains(index, "&lt;b&gt;first of its kind")
  let nvidia = simulate.read_body(get(pool, "/attempts?gpu=nvidia", ""))
  assert string.contains(nvidia, name)
  let amd = simulate.read_body(get(pool, "/attempts?gpu=amd", ""))
  assert !string.contains(amd, name)
  assert get(pool, path <> "/about", "").status == 404
  let mirrors = simulate.read_body(get(pool, path <> "/mirrors", ""))
  assert string.contains(mirrors, "href=\"magnet:?xt=urn:btih:abc\"")

  let entry = [#("status", "boots"), #("note", "reaches the logo")]
  assert send(pool, path <> "/progress", visitor, entry).status == 404
  assert send(pool, path <> "/progress", admin, entry).status == 303
  let progress = simulate.read_body(get(pool, path, ""))
  assert string.contains(progress, "reaches the logo")
  assert string.contains(progress, "status boots")

  let bad = [#("mirrors", "javascript:alert(1)"), ..fields]
  assert send(pool, path, admin, bad).status == 422
  assert send(pool, path <> "/delete", visitor, []).status == 404
  assert send(pool, path <> "/delete", admin, []).status == 303
  assert get(pool, path, "").status == 404
}

pub fn moderation_test() {
  let pool = open()
  let member = join(pool)
  let admin = wisp.random_string(64)
  let saved = user.save(pool, int.random(1_000_000_000), "admin")
  user.login(pool, saved.id, admin)
  let assert Ok(_) =
    pog.query("update users set admin = true where id = $1")
    |> pog.parameter(pog.int(saved.id))
    |> pog.execute(pool)
  let title = "pin " <> wisp.random_string(8)
  let id = submit(pool, member, title)
  let path = "/post/" <> int.to_string(id)

  assert send(pool, path <> "/pin", member, []).status == 404
  assert send(pool, path <> "/pin", admin, []).status == 303
  let assert Ok(found) = post.find(pool, 0, id)
  assert found.pinned
  assert string.contains(simulate.read_body(get(pool, "/community", "")), title)

  assert send(pool, path <> "/close", admin, []).status == 303
  let closed = send(pool, path <> "/comment", admin, [#("text", "too late")])
  assert string.contains(simulate.read_body(closed), "This thread is closed.")
  assert send(pool, path <> "/open", admin, []).status == 303
  assert send(pool, path <> "/unpin", admin, []).status == 303

  assert get(pool, "/submit", member).status == 200
  assert send(pool, path <> "/ban", admin, []).status == 303
  assert get(pool, "/submit", member).status == 303
  assert send(pool, path <> "/unban", admin, []).status == 303
  assert get(pool, "/submit", member).status == 200

  let rules = simulate.read_body(get(pool, "/community", ""))
  assert string.contains(rules, "Posting rules")
  assert string.contains(rules, "via System")
}

pub fn polls_test() {
  let pool = open()
  let voter = join(pool)
  let admin = wisp.random_string(64)
  let saved = user.save(pool, int.random(1_000_000_000), "admin")
  user.login(pool, saved.id, admin)
  let assert Ok(_) =
    pog.query("update users set admin = true where id = $1")
    |> pog.parameter(pog.int(saved.id))
    |> pog.execute(pool)
  let question = "Poll " <> wisp.random_string(8)
  let fields = [#("question", question), #("options", "first\nsecond")]
  let mine = fn() {
    let assert Ok(found) =
      list.find(poll.all(pool, 0), fn(found) { found.question == question })
    found
  }

  assert string.contains(
    simulate.read_body(get(pool, "/polls", "")),
    "Who will be first to run the game from start to finish?",
  )
  assert send(pool, "/polls", voter, fields).status == 404
  assert send(pool, "/polls", admin, [#("question", "x"), #("options", "one")]).status
    == 422
  assert send(pool, "/polls", admin, fields).status == 303
  let assert [first, _] = mine().choices
  let choose = fn(token, choice: poll_types.Choice) {
    send(pool, "/polls/vote", token, [#("option", int.to_string(choice.id))])
  }

  let res = choose("", first)
  assert list.key_find(res.headers, "location") == Ok("/login")
  let _ = choose(voter, first)
  let _ = choose(voter, first)
  let _ = choose(admin, first)
  let assert [first, second] = mine().choices
  assert #(first.votes, second.votes) == #(2, 0)
  let _ = choose(voter, second)
  let assert [first, second] = mine().choices
  assert #(first.votes, second.votes) == #(1, 1)

  let path = "/polls/" <> int.to_string(mine().id)
  assert send(pool, path <> "/close", voter, []).status == 404
  assert send(pool, path <> "/close", admin, []).status == 303
  let _ = choose(voter, first)
  let assert [first, _] = mine().choices
  assert first.votes == 1
  assert send(pool, path <> "/delete", admin, []).status == 303
}

pub fn limits_test() {
  let pool = open()
  let token = join(pool)
  let wide = string.repeat("a" <> string.repeat("\u{301}", 9), 60)
  let photo = FileUpload("shot.png", "image/png", <<"not a picture":utf8>>)
  let res =
    simulate.browser_request(http.Post, "/submit")
    |> simulate.cookie("session", token, wisp.PlainText)
    |> simulate.multipart_body(
      [#("title", "many"), #("text", "")],
      list.repeat(#("photo", photo), 40),
    )
    |> router.handle(pool, App("id", "secret"))

  assert string.contains(simulate.read_body(res), "at most 3 photos")
  assert send(pool, "/submit", token, [#("title", wide), #("text", "")]).status
    == 422
  assert !github.link("https://github.com/login/oauth/authorize?client_id=x")
  assert github.link("https://github.com/example/attempt")
}
