import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/result
import gleam/string
import pog.{type Connection}
import simplifile

pub fn start(url: String) -> Connection {
  let assert Ok(config) = pog.url_config(process.new_name("vitrack_db"), url)
  let assert Ok(pool) = pog.start(config)
  pool.data
}

pub fn migrate(db: Connection) -> Nil {
  let assert Ok(_) =
    pog.query("create table if not exists migrations (name text primary key)")
    |> pog.execute(db)
  let assert Ok(applied) =
    pog.query("select name from migrations")
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(db)
  let assert Ok(files) = simplifile.read_directory("db/migrations")

  files
  |> list.filter(fn(file) { !list.contains(applied.rows, file) })
  |> list.sort(string.compare)
  |> list.each(apply(db, _))
}

fn apply(db: Connection, file: String) -> Nil {
  let assert Ok(sql) = simplifile.read("db/migrations/" <> file)
  let assert Ok(_) =
    pog.transaction(db, fn(db) {
      use _ <- result.try(
        string.split(sql, ";")
        |> list.map(string.trim)
        |> list.filter(fn(statement) { statement != "" })
        |> list.try_each(fn(statement) {
          pog.query(statement) |> pog.execute(db)
        }),
      )
      pog.query("insert into migrations (name) values ($1)")
      |> pog.parameter(pog.text(file))
      |> pog.execute(db)
    })
  Nil
}
