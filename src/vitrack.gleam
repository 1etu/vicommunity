import envoy
import gleam/erlang/process
import mist
import vitrack/db
import vitrack/router
import vitrack/typs/github_types
import wisp
import wisp/wisp_mist

pub fn main() {
  let assert Ok(url) = envoy.get("DATABASE_URL")
  let assert Ok(id) = envoy.get("GITHUB_CLIENT_ID")
  let assert Ok(secret) = envoy.get("GITHUB_CLIENT_SECRET")
  let pool = db.start(url)
  db.migrate(pool)

  let assert Ok(_) =
    wisp_mist.handler(
      router.handle(_, pool, github_types.App(id:, secret:)),
      wisp.random_string(64),
    )
    |> mist.new
    |> mist.port(8001)
    |> mist.start
  //door ring wait brb
  process.sleep_forever()
}
