import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import pog.{type Connection}
import shellout
import simplifile
import vitrack/typs/photo_types.{type Photo, Photo}

pub fn convert(path: String, name: String) -> Result(Photo, Nil) {
  let assert Ok(bits) = simplifile.read_bits(path)
  let size = bit_array.byte_size(bits)
  use format <- result.try(case bits {
    _ if size > 8_000_000 -> Error(Nil)
    <<0xFF, 0xD8, 0xFF, _:bits>> -> Ok("jpeg_pipe")
    <<0x89, "PNG\r\n":utf8, 0x1A, 0x0A, _:bits>> -> Ok("png_pipe")
    <<"RIFF":utf8, _:32, "WEBP":utf8, _:bits>> -> Ok("webp_pipe")
    _ -> Error(Nil)
  })
  let assert Ok(_) = simplifile.create_directory_all("data/uploads")
  let file = name <> ".webp"
  use _ <- result.try(
    run("ffmpeg", [
      "-nostdin",
      "-v",
      "error",
      "-timelimit",
      "20",
      "-max_pixels",
      "40000000",
      "-f",
      format,
      "-i",
      path,
      "-frames:v",
      "1",
      "-vf",
      "scale='min(1600,iw)':'min(1600,ih)':force_original_aspect_ratio=decrease",
      "-map_metadata",
      "-1",
      "-y",
      "data/uploads/" <> file,
    ]),
  )
  let size =
    run("ffprobe", [
      "-v",
      "error",
      "-select_streams",
      "v:0",
      "-show_entries",
      "stream=width,height",
      "-of",
      "csv=p=0",
      "data/uploads/" <> file,
    ])
    |> result.unwrap("")
  case string.trim(size) |> string.split(",") |> list.map(int.parse) {
    [Ok(width), Ok(height)] -> Ok(Photo(file:, width:, height:))
    _ -> {
      discard([file])
      Error(Nil)
    }
  }
}

fn run(program: String, arguments: List(String)) -> Result(String, Nil) {
  shellout.command(run: program, with: arguments, in: ".", opt: [])
  |> result.replace_error(Nil)
}

pub fn save(db: Connection, post_id: Int, photos: List(Photo)) -> Nil {
  list.index_fold(photos, Nil, fn(_, photo, position) {
    let assert Ok(_) =
      pog.query(
        "insert into photos (post_id, position, file, width, height)
        values ($1, $2, $3, $4, $5)",
      )
      |> pog.parameter(pog.int(post_id))
      |> pog.parameter(pog.int(position))
      |> pog.parameter(pog.text(photo.file))
      |> pog.parameter(pog.int(photo.width))
      |> pog.parameter(pog.int(photo.height))
      |> pog.execute(db)
    Nil
  })
}

pub fn of(db: Connection, post_id: Int) -> List(Photo) {
  let assert Ok(found) =
    pog.query(
      "select file, width, height from photos
      where post_id = $1 order by position",
    )
    |> pog.parameter(pog.int(post_id))
    |> pog.returning({
      use file <- decode.field(0, decode.string)
      use width <- decode.field(1, decode.int)
      use height <- decode.field(2, decode.int)
      decode.success(Photo(file:, width:, height:))
    })
    |> pog.execute(db)
  found.rows
}

pub fn delete(db: Connection, post_id: Int) -> Nil {
  let assert Ok(deleted) =
    pog.query("delete from photos where post_id = $1 returning file")
    |> pog.parameter(pog.int(post_id))
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(db)
  discard(deleted.rows)
}

pub fn discard(files: List(String)) -> Nil {
  list.each(files, fn(file) { simplifile.delete("data/uploads/" <> file) })
}
