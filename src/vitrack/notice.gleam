import gleam/dynamic/decode
import pog.{type Connection}
import vitrack/github
import vitrack/typs/notice_types.{type Notice, Notice}

pub fn removes(db: Connection, user: Int, text: String) -> Bool {
  case github.only(text) {
    True -> False
    False -> {
      let assert Ok(_) =
        pog.query(
          "with added as (
            insert into notices (user_id, body) values ($1, left($2, 10000))
          )
          delete from notices
          where user_id = $1 and id not in (
            select id from notices
            where user_id = $1 order by id desc limit 19
          )",
        )
        |> pog.parameter(pog.int(user))
        |> pog.parameter(pog.text(text))
        |> pog.execute(db)
      True
    }
  }
}

pub fn of(db: Connection, user: Int) -> List(Notice) {
  let assert Ok(found) =
    pog.query(
      "select id, body, extract(epoch from now() - created_at)::int
      from notices where user_id = $1 order by created_at desc",
    )
    |> pog.parameter(pog.int(user))
    |> pog.returning({
      use id <- decode.field(0, decode.int)
      use body <- decode.field(1, decode.string)
      use age <- decode.field(2, decode.int)
      decode.success(Notice(id:, body:, age:))
    })
    |> pog.execute(db)
  found.rows
}

pub fn dismiss(db: Connection, user: Int, id: Int) -> Nil {
  let assert Ok(_) =
    pog.query("delete from notices where id = $1 and user_id = $2")
    |> pog.parameter(pog.int(id))
    |> pog.parameter(pog.int(user))
    |> pog.execute(db)
  Nil
}
