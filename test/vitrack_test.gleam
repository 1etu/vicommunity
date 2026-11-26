import envoy
import gleeunit
import vitrack/db

pub fn main() {
  let assert Ok(url) = envoy.get("DATABASE_URL")
  db.migrate(db.start(url))

  gleeunit.main()
}
