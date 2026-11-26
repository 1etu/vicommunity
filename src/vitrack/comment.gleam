import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pog.{type Connection}
import vitrack/language
import vitrack/typs/comment_types.{type Comment, Comment}

const columns =
  "c.id, c.post_id, coalesce(c.parent_id, 0), c.depth, c.body,
  c.score, extract(epoch from now() - c.created_at)::int, c.deleted,
  u.id, u.login, u.github_id, coalesce(v.value, 0), u.banned"

const joins =
  "join users u on u.id = c.user_id
  left join comment_votes v on v.comment_id = c.id and v.user_id = $1"

pub fn tree(db: Connection, viewer: Int, post_id: Int) -> List(Comment) {
  let assert Ok(found) =
    pog.query("select " <> columns <> "
      from comments c " <> joins <> "
      where c.post_id = $2
      order by c.score desc, c.created_at")
    |> pog.parameter(pog.int(viewer))
    |> pog.parameter(pog.int(post_id))
    |> pog.returning(decoder())
    |> pog.execute(db)

  found.rows
  |> list.reverse
  |> list.group(fn(comment) { comment.parent_id })
  |> nest(0)
}

fn nest(children: Dict(Int, List(Comment)), parent: Int) -> List(Comment) {
  dict.get(children, parent)
  |> result.unwrap([])
  |> list.map(fn(comment) {
    Comment(..comment, replies: nest(children, comment.id))
  })
  |> list.filter(fn(comment) { !comment.deleted || comment.replies != [] })
}

pub fn find(db: Connection, viewer: Int, id: Int) -> Result(Comment, Nil) {
  let assert Ok(found) =
    pog.query("select " <> columns <> "
      from comments c " <> joins <> "
      where c.id = $2 and not c.deleted")
    |> pog.parameter(pog.int(viewer))
    |> pog.parameter(pog.int(id))
    |> pog.returning(decoder())
    |> pog.execute(db)
  case found.rows {
    [comment] -> Ok(comment)
    _ -> Error(Nil)
  }
}

pub fn create(
  db: Connection,
  user: Int,
  post_id: Int,
  parent_id: Int,
  body: String,
) -> Result(Int, String) {
  let body = string.trim(body)
  use <- bool.guard(body == "", Error("A comment cannot be empty."))
  use <- bool.guard(
    string.length(body) > 10_000 || string.byte_size(body) > 40_000,
    Error("Comments can be at most 10,000 characters."),
  )
  use <- bool.guard(
    string.contains(body, "\u{0}"),
    Error("Text cannot contain null characters."),
  )
  use _ <- result.try(language.check(body))
  let assert Ok(created) =
    pog.transaction(db, fn(db) {
      use _ <- result.try(
        pog.query("select pg_advisory_xact_lock($1)::text")
        |> pog.parameter(pog.int(user))
        |> pog.execute(db),
      )
      use locked <- result.try(
        pog.query(
          "select 1 from posts
          where id = $1 and not deleted and not locked
            and comment_count < 1000
          for update",
        )
        |> pog.parameter(pog.int(post_id))
        |> pog.execute(db),
      )
      use <- bool.guard(locked.count == 0, Ok(None))
      use created <- result.try(
        pog.query(
          "with created as (
            insert into comments (post_id, parent_id, depth, user_id, body)
            select $1::bigint, nullif($2::bigint, 0),
              coalesce(parent.depth + 1, 0), $3::bigint, $4::text
            from (select 1) one
            left join comments parent on parent.id = $2
              and parent.post_id = $1
              and not parent.deleted
              and parent.depth < 10
            where ($2 = 0 or parent.id is not null)
              and not exists (
                select 1 from comments
                where user_id = $3
                  and created_at > now() - interval '30 seconds'
              )
            returning id
          ), voted as (
            insert into comment_votes (comment_id, user_id, value)
            select id, $3, 1 from created
          )
          select id from created",
        )
        |> pog.parameter(pog.int(post_id))
        |> pog.parameter(pog.int(parent_id))
        |> pog.parameter(pog.int(user))
        |> pog.parameter(pog.text(body))
        |> pog.returning(decode.at([0], decode.int))
        |> pog.execute(db),
      )
      use _ <- result.try(count(db, post_id))
      Ok(Some(created.rows))
    })
  case created {
    Some([id]) -> Ok(id)
    Some(_) -> Error("You're posting too fast. Please slow down. Thanks.")
    None -> Error("This thread is closed.")
  }
}

pub fn vote(
  db: Connection,
  user: Int,
  id: Int,
  value: Int,
) -> Result(Int, Nil) {
  let assert Ok(locked) =
    pog.transaction(db, fn(db) {
      use locked <- result.try(
        pog.query(
          "select post_id from comments
          where id = $1 and not deleted for update",
        )
        |> pog.parameter(pog.int(id))
        |> pog.returning(decode.at([0], decode.int))
        |> pog.execute(db),
      )
      use <- bool.guard(locked.count == 0, Ok([]))
      use _ <- result.try(
        case value {
          0 ->
            pog.query(
              "delete from comment_votes where comment_id = $1 and user_id = $2",
            )
            |> pog.parameter(pog.int(id))
            |> pog.parameter(pog.int(user))
          _ ->
            pog.query(
              "insert into comment_votes (comment_id, user_id, value)
              values ($1, $2, $3)
              on conflict (comment_id, user_id) do update set value = excluded.value",
            )
            |> pog.parameter(pog.int(id))
            |> pog.parameter(pog.int(user))
            |> pog.parameter(pog.int(value))
        }
        |> pog.execute(db),
      )
      use _ <- result.try(
        pog.query(
          "update comments set score = (
            select coalesce(sum(value), 0) from comment_votes
            where comment_id = $1
          ) where id = $1",
        )
        |> pog.parameter(pog.int(id))
        |> pog.execute(db),
      )
      Ok(locked.rows)
    })
  list.first(locked)
}

pub fn delete(db: Connection, id: Int) -> Nil {
  let assert Ok(_) =
    pog.transaction(db, fn(db) {
      use deleted <- result.try(
        pog.query(
          "update comments set deleted = true, body = ''
          where id = $1 returning post_id",
        )
        |> pog.parameter(pog.int(id))
        |> pog.returning(decode.at([0], decode.int))
        |> pog.execute(db),
      )
      list.try_each(deleted.rows, count(db, _))
    })
  Nil
}

fn count(db: Connection, post_id: Int) -> Result(Nil, pog.QueryError) {
  pog.query(
    "update posts set comment_count = (
      select count(*) from comments where post_id = $1 and not deleted
    ) where id = $1",
  )
  |> pog.parameter(pog.int(post_id))
  |> pog.execute(db)
  |> result.replace(Nil)
}

fn decoder() -> Decoder(Comment) {
  use id <- decode.field(0, decode.int)
  use post_id <- decode.field(1, decode.int)
  use parent_id <- decode.field(2, decode.int)
  use depth <- decode.field(3, decode.int)
  use body <- decode.field(4, decode.string)
  use score <- decode.field(5, decode.int)
  use age <- decode.field(6, decode.int)
  use deleted <- decode.field(7, decode.bool)
  use user_id <- decode.field(8, decode.int)
  use login <- decode.field(9, decode.string)
  use github_id <- decode.field(10, decode.int)
  use vote <- decode.field(11, decode.int)
  use banned <- decode.field(12, decode.bool)
  decode.success(
    Comment(
      id:,
      post_id:,
      parent_id:,
      depth:,
      body:,
      score:,
      age:,
      deleted:,
      user_id:,
      login:,
      github_id:,
      vote:,
      banned:,
      replies: [],
    ),
  )
}
