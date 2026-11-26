import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string
import pog.{type Connection}
import vitrack/typs/poll_types.{type Poll, Choice, Poll}

pub fn all(db: Connection, viewer: Int) -> List(Poll) {
  let assert Ok(choices) =
    pog.query(
      "select o.poll_id, o.id, o.label, (
        select count(*) from poll_votes v where v.option_id = o.id
      )
      from poll_options o order by o.poll_id, o.position desc",
    )
    |> pog.returning({
      use poll_id <- decode.field(0, decode.int)
      use id <- decode.field(1, decode.int)
      use label <- decode.field(2, decode.string)
      use votes <- decode.field(3, decode.int)
      decode.success(#(poll_id, Choice(id:, label:, votes:)))
    })
    |> pog.execute(db)
  let grouped = list.group(choices.rows, fn(row) { row.0 })
  let assert Ok(polls) =
    pog.query(
      "select p.id, p.question, u.login,
        extract(epoch from now() - p.created_at)::int, p.closed,
        coalesce(v.option_id, 0)
      from polls p
      join users u on u.id = p.user_id
      left join poll_votes v on v.poll_id = p.id and v.user_id = $1
      order by p.created_at desc, p.id desc",
    )
    |> pog.parameter(pog.int(viewer))
    |> pog.returning({
      use id <- decode.field(0, decode.int)
      use question <- decode.field(1, decode.string)
      use login <- decode.field(2, decode.string)
      use age <- decode.field(3, decode.int)
      use closed <- decode.field(4, decode.bool)
      use mine <- decode.field(5, decode.int)
      decode.success(Poll(
        id:,
        question:,
        login:,
        age:,
        closed:,
        mine:,
        choices: dict.get(grouped, id)
          |> result.unwrap([])
          |> list.map(fn(row) { row.1 }),
      ))
    })
    |> pog.execute(db)
  polls.rows
}

pub fn create(
  db: Connection,
  user: Int,
  question: String,
  choices: String,
) -> Result(Nil, String) {
  let question = string.trim(question)
  let choices =
    string.split(string.replace(choices, "\r", ""), "\n")
    |> list.map(string.trim)
    |> list.filter(fn(choice) { choice != "" })
  use <- bool.guard(
    question == "" || string.length(question) > 200,
    Error("A question of at most 200 characters is required."),
  )
  use <- bool.guard(
    list.length(choices) < 2 || list.length(choices) > 20,
    Error("A poll needs between 2 and 20 options, one per line."),
  )
  use <- bool.guard(
    list.any(choices, fn(choice) { string.length(choice) > 100 })
      || string.contains(question <> string.concat(choices), "\u{0}"),
    Error("Each option can be at most 100 characters."),
  )
  let assert Ok(_) =
    pog.query(
      "with created as (
        insert into polls (user_id, question) values ($1, $2) returning id
      )
      insert into poll_options (poll_id, position, label)
      select created.id, o.position, o.label
      from created, unnest($3::text[]) with ordinality as o (label, position)",
    )
    |> pog.parameter(pog.int(user))
    |> pog.parameter(pog.text(question))
    |> pog.parameter(pog.array(pog.text, choices))
    |> pog.execute(db)
  Ok(Nil)
}

pub fn vote(db: Connection, user: Int, choice: Int) -> Nil {
  let assert Ok(_) =
    pog.query(
      "insert into poll_votes (poll_id, user_id, option_id)
      select o.poll_id, $1, o.id
      from poll_options o
      join polls p on p.id = o.poll_id
      where o.id = $2 and not p.closed
      on conflict (poll_id, user_id)
      do update set option_id = excluded.option_id",
    )
    |> pog.parameter(pog.int(user))
    |> pog.parameter(pog.int(choice))
    |> pog.execute(db)
  Nil
}

pub fn close(db: Connection, id: Int, closed: Bool) -> Nil {
  let assert Ok(_) =
    pog.query("update polls set closed = $2 where id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.parameter(pog.bool(closed))
    |> pog.execute(db)
  Nil
}

pub fn delete(db: Connection, id: Int) -> Nil {
  let assert Ok(_) =
    pog.query("delete from polls where id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.execute(db)
  Nil
}
