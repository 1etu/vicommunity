import gleam/list
import shellout
import simplifile
import vitrack/photo

pub fn convert_test() {
  let assert Ok(_) =
    shellout.command(
      run: "ffmpeg",
      with: [
        "-nostdin", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=3000x2000",
        "-frames:v", "1", "-y", "build/plain.jpg",
      ],
      in: ".",
      opt: [],
    )
  let assert Ok(<<start:bytes-size(2), rest:bits>>) =
    simplifile.read_bits("build/plain.jpg")
  let sideways = <<
    start:bits,
    0xFF,
    0xE1,
    34:size(16),
    "Exif":utf8,
    0:size(16),
    "II":utf8,
    42:size(16)-little,
    8:size(32)-little,
    1:size(16)-little,
    0x0112:size(16)-little,
    3:size(16)-little,
    1:size(32)-little,
    6:size(32)-little,
    0:size(32)-little,
    rest:bits,
  >>
  let assert Ok(_) = simplifile.write_bits("build/sideways.jpg", sideways)

  let assert Ok(made) = photo.convert("build/sideways.jpg", "test")
  let assert Ok(<<"RIFF":utf8, _:size(32), "WEBP":utf8, body:bits>>) =
    simplifile.read_bits("data/uploads/" <> made.file)
  photo.discard([made.file])

  assert made.width == 1067
  assert made.height == 1600
  assert !list.contains(chunks(body), <<"EXIF":utf8>>)
  assert !list.contains(chunks(body), <<"XMP ":utf8>>)
}

pub fn disguised_test() {
  let assert Ok(_) = simplifile.write("build/fake.png", "not a picture")

  assert photo.convert("build/fake.png", "fake") == Error(Nil)
}

fn chunks(bits: BitArray) -> List(BitArray) {
  case bits {
    <<name:bytes-size(4), size:size(32)-little, rest:bits>> -> {
      let padded = size + size % 2
      case rest {
        <<_:bytes-size(padded), next:bits>> -> [name, ..chunks(next)]
        _ -> [name]
      }
    }
    _ -> []
  }
}
