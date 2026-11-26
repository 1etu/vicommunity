import gleam/dynamic/decode.{type Decoder}
import pog.{type Connection}
import vitrack/typs/user_types.{type User, User}

pub fn save(db: Connection, github_id: Int, login: String) -> User {
  let assert Ok(pog.Returned(rows: [user], ..)) =
    pog.query(
      "insert into users (github_id, login) values ($1, $2)
      on conflict (github_id) do update set login = excluded.login
      returning id, github_id, login, admin, 0",
    )
    |> pog.parameter(pog.int(github_id))
    |> pog.parameter(pog.text(login))
    |> pog.returning(decoder())
    |> pog.execute(db)
  user
}

pub fn login(db: Connection, id: Int, token: String) -> Nil {
  let assert Ok(_) =
    pog.query(
      "delete from sessions where created_at < now() - interval '30 days'",
    )
    |> pog.execute(db)
  let assert Ok(_) =
    pog.query(
      "insert into sessions (token_hash, user_id)
      values (sha256(convert_to($1, 'utf8')), $2)",
    )
    |> pog.parameter(pog.text(token))
    |> pog.parameter(pog.int(id))
    |> pog.execute(db)
  Nil
}

pub fn logout(db: Connection, token: String) -> Nil {
  let assert Ok(_) =
    pog.query(
      "delete from sessions where token_hash = sha256(convert_to($1, 'utf8'))",
    )
    |> pog.parameter(pog.text(token))
    |> pog.execute(db)
  Nil
}

pub fn ban(db: Connection, id: Int, banned: Bool) -> Nil {
  let assert Ok(_) =
    pog.query("update users set banned = $2 where id = $1 and not admin")
    |> pog.parameter(pog.int(id))
    |> pog.parameter(pog.bool(banned))
    |> pog.execute(db)
  Nil
}

pub fn current(db: Connection, token: String) -> Result(User, Nil) {
  let assert Ok(found) =
    pog.query(
      "select u.id, u.github_id, u.login, u.admin,
        (select count(*) from notices n where n.user_id = u.id)
      from sessions s
      join users u on u.id = s.user_id
      where s.token_hash = sha256(convert_to($1, 'utf8'))
        and s.created_at > now() - interval '30 days'
        and not u.banned",
    )
    |> pog.parameter(pog.text(token))
    |> pog.returning(decoder())
    |> pog.execute(db)
  case found.rows {
    [user] -> Ok(user)
    _ -> Error(Nil)
  }
}

fn decoder() -> Decoder(User) {
  use id <- decode.field(0, decode.int)
  use github_id <- decode.field(1, decode.int)
  use login <- decode.field(2, decode.string)
  use admin <- decode.field(3, decode.bool)
  use notices <- decode.field(4, decode.int)
  decode.success(User(id:, github_id:, login:, admin:, notices:))
}

fn dodecoderworkiwonder() -> Decoder(User) {
  todo
}
