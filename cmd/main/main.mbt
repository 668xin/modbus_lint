// CLI entry point for modbus_lint.
//
// Usage:
//   moon run cmd/main -- --demo                        lint the built-in demo table
//   moon run cmd/main -- --format summary --demo       demo report in summary form
//   moon run cmd/main -- "a 40001 int16 R"             lint register lines given as args
//   moon run cmd/main -- --json-in "$(cat table.json)" lint a JSON point table
//   moon run cmd/main -- --gap 32 --show "a 40001..."  raise gap threshold + show sorted table
//   moon run cmd/main -- --encode float32 1.5          pack a float into words + bytes
//   moon run cmd/main -- --encode uint32 4294967295    pack an unsigned 32-bit value
//   moon run cmd/main -- --decode int32 ffff 8000      rebuild a signed value from words
//   moon run cmd/main -- --help                        show usage
//
// Options:
//   --json        alias for --format json
//   --format FMT  report format: text | json | markdown | summary (default text)
//   --gap N       override the Rule-6 max address gap threshold (words)
//   --json-in J   read the point table from a JSON document instead of text lines
//   --show        print the point table sorted by address before the report
//   --encode T V  encode VALUE V of TYPE T (int16|uint16|int32|uint32|float32|float64)
//   --decode T W  decode hex tokens: 4-digit words (MSW first) or 2-digit wire bytes
//   --order BO    byte order for the *bytes* view: big | little (default big)
//   --word-order WO  word order for int32/uint32: hi-lo | lo-hi (default hi-lo)
//   --demo        lint the built-in demo point table
//   --help        show this help
//
// The CLI depends only on moonbitlang/core (`env` + `println`), so it runs
// anywhere MoonBit runs, without extra dependencies.

///|
/// Output format of the report.
enum OutputFormat {
  Text
  Json
  Markdown
  Summary
  Csv
  Html
}

///|
fn main {
  let args = @env.args()
  let mut fmt = Text
  let mut gap_opt : Int? = None
  let mut json_in = ""
  let mut show = false
  let mut use_demo = false
  let mut want_stats = false
  // Value-encoding command state: `--encode` packs a number into register
  // words/bytes, `--decode` rebuilds a number from words given as hex tokens.
  let mut enc_is_encode = true
  let mut enc_type = ""
  let mut enc_val = ""
  let mut byte_order = "big"
  let mut word_order = "hi-lo"
  let lines : Array[String] = []
  // args[0] is the executable path itself, so user arguments start at index 1.
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--json" {
      fmt = Json
    } else if a == "--format" {
      if i + 1 < args.length() {
        fmt = parse_format(args[i + 1])
        i = i + 1
      } else {
        println("--format requires an argument (text|json|markdown|summary)")
        return
      }
    } else if a == "--gap" {
      if i + 1 < args.length() {
        gap_opt = parse_int(args[i + 1])
        i = i + 1
      } else {
        println("--gap requires an integer argument")
        return
      }
    } else if a == "--json-in" {
      if i + 1 < args.length() {
        json_in = args[i + 1]
        i = i + 1
      } else {
        println("--json-in requires a JSON document as its argument")
        return
      }
    } else if a == "--show" {
      show = true
    } else if a == "--demo" {
      use_demo = true
    } else if a == "--stats" {
      want_stats = true
    } else if a == "--encode" {
      if i + 2 < args.length() {
        enc_is_encode = true
        enc_type = args[i + 1]
        enc_val = args[i + 2]
        i = i + 2
      } else {
        println("--encode requires TYPE and VALUE (e.g. --encode float32 1.5)")
        return
      }
    } else if a == "--decode" {
      if i + 1 < args.length() {
        enc_is_encode = false
        enc_type = args[i + 1]
        i = i + 1
      } else {
        println("--decode requires a TYPE (e.g. --decode float32 3fc0 0000)")
        return
      }
    } else if a == "--order" {
      if i + 1 < args.length() {
        byte_order = args[i + 1]
        i = i + 1
      } else {
        println("--order requires big or little")
        return
      }
    } else if a == "--word-order" {
      if i + 1 < args.length() {
        word_order = args[i + 1]
        i = i + 1
      } else {
        println("--word-order requires hi-lo or lo-hi")
        return
      }
    } else if a == "--help" {
      print_usage()
      return
    } else {
      lines.push(a)
    }
    i = i + 1
  }

  // A value-encoding request short-circuits the linter entirely.
  if enc_type != "" {
    run_encode(enc_is_encode, enc_type, enc_val, lines, byte_order, word_order)
    return
  }

  if use_demo {
    run_device(
      @modbus_lint.parse_device(example_text()),
      fmt,
      gap_opt,
      show,
      want_stats,
    )
    return
  }
  if json_in != "" {
    run_device(
      @modbus_lint.parse_device_json(json_in),
      fmt,
      gap_opt,
      show,
      want_stats,
    )
    return
  }
  if lines.length() == 0 {
    println("no input given; running the built-in demo point table:")
    println("")
    run_device(
      @modbus_lint.parse_device(example_text()),
      fmt,
      gap_opt,
      show,
      want_stats,
    )
    return
  }
  run_device(
    @modbus_lint.parse_device(join_lines(lines)),
    fmt,
    gap_opt,
    show,
    want_stats,
  )
}

///|
/// Print the CLI help text.
fn print_usage() -> Unit {
  println("modbus_lint - Modbus point table linter")
  println("")
  println("usage: moon run cmd/main -- [options] [register lines...]")
  println("")
  println("options:")
  println(
    "  --format FMT   报告格式: text | json | markdown | summary | csv | html（默认 text）",
  )
  println("  --json         --format json 的别名")
  println(
    "  --gap N        覆盖 Rule 6 最大地址间隙阈值（字，默认 16）",
  )
  println("  --json-in J    从 JSON 文档读取点表（而非文本行）")
  println("  --show         在报告前打印按地址排序后的点表")
  println("  --stats        打印点表统计摘要并退出")
  println("  --demo         校验内置演示点表")
  println(
    "  --encode T V   将数值 V（类型 T=int16|uint16|int32|uint32|float32|float64）编码为寄存器字/字节",
  )
  println(
    "  --decode T W   反解数值：4 位十六制字，或 2 位线上字节",
  )
  println(
    "  --order BO     *字节视图*字节序: big | little（默认 big）",
  )
  println(
    "  --word-order WO int32/uint32 字序: hi-lo | lo-hi（默认 hi-lo）",
  )
  println("  --help         显示本帮助")
}

///|
/// Parse the `--format` argument into an `OutputFormat`.
fn parse_format(s : String) -> OutputFormat {
  if s == "json" {
    Json
  } else if s == "markdown" {
    Markdown
  } else if s == "summary" {
    Summary
  } else if s == "csv" {
    Csv
  } else if s == "html" {
    Html
  } else {
    Text
  }
}

///|
/// Parse a non-negative integer argument, returning `None` on bad input.
fn parse_int(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut n = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// Resolve the `--order` argument to a `ByteOrder`.
fn resolve_order(s : String) -> @modbus_lint.ByteOrder {
  @modbus_lint.byte_order_of(s)
}

///|
/// Parse a decimal `Double` literal (with optional sign, fraction, and `e`
/// exponent) into a value, or `None` if the text is not a valid number.
fn parse_double(s : String) -> Double? {
  if s.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  let c0 = s[i].to_int().unsafe_to_char()
  if c0 == '-' {
    neg = true
    i = i + 1
  } else if c0 == '+' {
    i = i + 1
  }
  // Integer part.
  let mut int_part = 0.0
  let mut has_digits = false
  while i < s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      int_part = int_part * 10.0 + (c.to_int() - '0'.to_int()).to_double()
      has_digits = true
      i = i + 1
    } else {
      break
    }
  }
  // Fractional part.
  let mut frac = 0.0
  if i < s.length() && s[i].to_int().unsafe_to_char() == '.' {
    i = i + 1
    let mut scale = 0.1
    while i < s.length() {
      let c = s[i].to_int().unsafe_to_char()
      if c >= '0' && c <= '9' {
        frac = frac + (c.to_int() - '0'.to_int()).to_double() * scale
        scale = scale * 0.1
        has_digits = true
        i = i + 1
      } else {
        break
      }
    }
  }
  if !has_digits {
    return None
  }
  // Optional `e`/`E` exponent.
  let mut e10 = 0
  if i < s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if c == 'e' || c == 'E' {
      i = i + 1
      let mut eneg = false
      if i < s.length() {
        let sc = s[i].to_int().unsafe_to_char()
        if sc == '-' {
          eneg = true
          i = i + 1
        } else if sc == '+' {
          i = i + 1
        }
      }
      let mut eint = 0
      let mut ed = false
      while i < s.length() {
        let cc = s[i].to_int().unsafe_to_char()
        if cc >= '0' && cc <= '9' {
          eint = eint * 10 + (cc.to_int() - '0'.to_int())
          ed = true
          i = i + 1
        } else {
          break
        }
      }
      if !ed {
        return None
      }
      e10 = if eneg { -eint } else { eint }
    } else {
      return None
    }
  }
  if i != s.length() {
    return None
  }
  let mut v = (int_part + frac) * @math.pow(10.0, e10.to_double())
  if neg {
    v = -v
  }
  Some(v)
}

///|
/// Parse a signed 32-bit integer literal into an `Int`, or `None` if the text
/// is not an integral value in `(-2^31, 2^31)`.
fn parse_int32(s : String) -> Int? {
  match parse_double(s) {
    None => None
    Some(d) => {
      if d < -2147483648.0 || d > 2147483647.0 {
        return None
      }
      if d.to_int().to_double() != d {
        return None // not an integer
      }
      Some(d.to_int())
    }
  }
}

///|
/// Parse an unsigned 32-bit literal (`0..=4294967295`) into its two's-complement
/// `Int` form (values above 2^31 become negative), or `None` on bad input.
fn parse_uint32(s : String) -> Int? {
  match parse_double(s) {
    None => None
    Some(d) => {
      if d < 0.0 || d >= 4294967296.0 {
        return None
      }
      if d != d.round() {
        return None // not an integer
      }
      if d <= 2147483647.0 {
        Some(d.to_int())
      } else {
        // Above 2^31: shift into the lower half so the result fits `Int` as a
        // two's-complement negative (e.g. 4294967295 -> -1).
        Some((d - 4294967296.0).to_int())
      }
    }
  }
}

///|
/// Parse a signed 16-bit integer literal (-32768..=32767), or `None`.
fn parse_int16(s : String) -> Int? {
  match parse_double(s) {
    None => None
    Some(d) => {
      if d < -32768.0 || d > 32767.0 {
        return None
      }
      if d != d.round() {
        return None
      }
      Some(d.to_int())
    }
  }
}

///|
/// Parse an unsigned 16-bit literal (0..=65535), or `None`.
fn parse_uint16(s : String) -> Int? {
  match parse_double(s) {
    None => None
    Some(d) => {
      if d < 0.0 || d > 65535.0 {
        return None
      }
      if d != d.round() {
        return None
      }
      Some(d.to_int())
    }
  }
}

///|
/// Render an `Int` holding a 32-bit two's-complement value as its unsigned
/// decimal form (`0..=4294967295`).
fn unsigned32_str(v : Int) -> String {
  if v >= 0 {
    Int64::from_int(v).to_string()
  } else {
    (4294967296L + Int64::from_int(v)).to_string()
  }
}

///|
/// Hex value of a character, or `None` for non-hex input.
fn hex_val(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Parse a hex string that must contain exactly `n` hex digits.
fn parse_hex_n(s : String, n : Int) -> Int? {
  if s.length() != n {
    return None
  }
  let mut v = 0
  for i = 0; i < n; i = i + 1 {
    match hex_val(s[i].to_int().unsafe_to_char()) {
      None => return None
      Some(h) => v = v * 16 + h
    }
  }
  Some(v)
}

///|
/// One hex digit as an uppercase character.
fn hex_digit(n : Int) -> String {
  if n < 10 {
    ('0'.to_int() + n).unsafe_to_char().to_string()
  } else {
    ('A'.to_int() + n - 10).unsafe_to_char().to_string()
  }
}

///|
/// A 4-digit uppercase hex word, e.g. `0x3FC0` renders as `3FC0`.
fn hex_word(w : Int) -> String {
  hex_digit((w >> 12) & 0xF) +
  hex_digit((w >> 8) & 0xF) +
  hex_digit((w >> 4) & 0xF) +
  hex_digit(w & 0xF)
}

///|
/// A 2-digit uppercase hex byte.
fn hex_byte(b : Int) -> String {
  hex_digit((b >> 4) & 0xF) + hex_digit(b & 0xF)
}

///|
/// Render an array of bytes as `0xHH 0xHH ...`.
fn bytes_str(bs : Array[Int]) -> String {
  let mut out = ""
  for b in bs {
    if out.length() > 0 {
      out = out + " "
    }
    out = out + "0x" + hex_byte(b)
  }
  out
}

///|
/// Parse every token as a two-digit hex byte, or `None` if any token is bad.
fn parse_hex_bytes(tokens : Array[String]) -> Array[Int]? {
  let out : Array[Int] = []
  for t in tokens {
    match parse_hex_n(t, 2) {
      None => return None
      Some(b) => out.push(b)
    }
  }
  Some(out)
}

///|
/// Encode a numeric value into (or decode it from) Modbus register words.
///
/// `--encode` takes a VALUE; `--decode` takes positional hex tokens. Decoded
/// tokens are read as words (4 hex digits, MSW first) OR, when the count points
/// to a byte payload, as individual wire bytes (2 hex digits each) reassembled
/// under the selected `--order` (and `--word-order` for 32-bit integers).
fn run_encode(
  is_encode : Bool,
  ty : String,
  val : String,
  tokens : Array[String],
  order_s : String,
  word_order_s : String,
) -> Unit {
  let order = resolve_order(order_s)
  let wo = @modbus_lint.word_order_of(word_order_s)
  let woName = @modbus_lint.word_order_name(wo)
  if is_encode {
    match parse_double(val) {
      None => {
        println("cannot parse value: " + val)
        return
      }
      Some(v) =>
        if ty == "float32" {
          let (hi, lo) = @modbus_lint.float32_words(v)
          let bs = @modbus_lint.float32_bytes(v, order)
          println("float32 = " + val)
          println(
            "  words (MSW first): 0x" + hex_word(hi) + " 0x" + hex_word(lo),
          )
          println(
            "  bytes (" +
            @modbus_lint.byte_order_name(order) +
            "): " +
            bytes_str(bs),
          )
        } else if ty == "float64" {
          let (w0, w1, w2, w3) = @modbus_lint.float64_words(v)
          let bs = @modbus_lint.float64_bytes(v, order)
          println("float64 = " + val)
          println(
            "  words (MSW first): 0x" +
            hex_word(w0) +
            " 0x" +
            hex_word(w1) +
            " 0x" +
            hex_word(w2) +
            " 0x" +
            hex_word(w3),
          )
          println(
            "  bytes (" +
            @modbus_lint.byte_order_name(order) +
            "): " +
            bytes_str(bs),
          )
        } else if ty == "int32" || ty == "uint32" {
          let parsed = if ty == "int32" {
            parse_int32(val)
          } else {
            parse_uint32(val)
          }
          match parsed {
            None => {
              println("invalid " + ty + ": " + val)
              return
            }
            Some(v) => {
              let (w0, w1) = @modbus_lint.int32_words(v, wo)
              let bs = @modbus_lint.encode_int32_bytes(v, order, wo)
              if ty == "int32" {
                println("int32 = " + val)
              } else {
                println(
                  "uint32 = " + val + " (unsigned " + unsigned32_str(v) + ")",
                )
              }
              println(
                "  words (" +
                woName +
                "): 0x" +
                hex_word(w0) +
                " 0x" +
                hex_word(w1),
              )
              println(
                "  bytes (" +
                @modbus_lint.byte_order_name(order) +
                " + " +
                woName +
                "): " +
                bytes_str(bs),
              )
            }
          }
        } else if ty == "int16" || ty == "uint16" {
          let parsed = if ty == "int16" {
            parse_int16(val)
          } else {
            parse_uint16(val)
          }
          match parsed {
            None => {
              println("invalid " + ty + ": " + val)
              return
            }
            Some(v) => {
              let w = @modbus_lint.encode_uint16(v)
              let bs = @modbus_lint.int16_bytes(v, order)
              if ty == "int16" {
                println("int16 = " + val + " (signed " + v.to_string() + ")")
              } else {
                println("uint16 = " + val)
              }
              println("  word: 0x" + hex_word(w))
              println(
                "  bytes (" +
                @modbus_lint.byte_order_name(order) +
                "): " +
                bytes_str(bs),
              )
            }
          }
        } else {
          println(
            "unknown type: " + ty + " (expected float32|float64|int32|uint32)",
          )
        }
    }
    return
  }
  // -------------------------------------------------------------------------
  // Decode: tokens may be words (4 hex digits, MSW first) or, for a byte-count
  // match, raw wire bytes (2 hex digits) reassembled under the selected order.
  // -------------------------------------------------------------------------
  if ty == "float32" {
    if tokens.length() == 2 {
      let hi = parse_hex_n(tokens[0], 4)
      let lo = parse_hex_n(tokens[1], 4)
      match (hi, lo) {
        (Some(h), Some(l)) =>
          println(
            "float32 0x" +
            tokens[0] +
            " 0x" +
            tokens[1] +
            " = " +
            @modbus_lint.float32_from_words(h, l).to_string(),
          )
        _ => ()
      }
    } else if tokens.length() == 4 {
      match parse_hex_bytes(tokens) {
        Some(bs) =>
          println(
            "float32 [" +
            @modbus_lint.byte_order_name(order) +
            "] = " +
            @modbus_lint.float32_from_bytes(bs, order).to_string(),
          )
        None => println("float32 bytes must be two-digit hex")
      }
    } else {
      println("float32 decode needs 2 words or 4 bytes")
    }
    return
  }
  if ty == "float64" {
    if tokens.length() == 4 {
      let w0 = parse_hex_n(tokens[0], 4)
      let w1 = parse_hex_n(tokens[1], 4)
      let w2 = parse_hex_n(tokens[2], 4)
      let w3 = parse_hex_n(tokens[3], 4)
      match (w0, w1, w2, w3) {
        (Some(a), Some(b), Some(c), Some(d)) =>
          println(
            "float64 = " +
            @modbus_lint.float64_from_words(a, b, c, d).to_string(),
          )
        _ => ()
      }
    } else if tokens.length() == 8 {
      match parse_hex_bytes(tokens) {
        Some(bs) =>
          println(
            "float64 [" +
            @modbus_lint.byte_order_name(order) +
            "] = " +
            @modbus_lint.float64_from_bytes(bs, order).to_string(),
          )
        None => println("float64 bytes must be two-digit hex")
      }
    } else {
      println("float64 decode needs 4 words or 8 bytes")
    }
    return
  }
  if ty == "int32" || ty == "uint32" {
    if tokens.length() == 2 {
      let hi = parse_hex_n(tokens[0], 4)
      let lo = parse_hex_n(tokens[1], 4)
      match (hi, lo) {
        (Some(h), Some(l)) => {
          let v = @modbus_lint.int32_fold_words(h, l, wo)
          if ty == "int32" {
            println(
              "int32 0x" + tokens[0] + " 0x" + tokens[1] + " = " + v.to_string(),
            )
          } else {
            println(
              "uint32 0x" +
              tokens[0] +
              " 0x" +
              tokens[1] +
              " = " +
              unsigned32_str(v),
            )
          }
        }
        _ => ()
      }
      return
    }
    if tokens.length() == 4 {
      match parse_hex_bytes(tokens) {
        Some(bs) => {
          let v = @modbus_lint.decode_int32_bytes(bs, order, wo)
          if ty == "int32" {
            println(
              "int32 [" +
              @modbus_lint.byte_order_name(order) +
              " " +
              woName +
              "] = " +
              v.to_string(),
            )
          } else {
            println(
              "uint32 [" +
              @modbus_lint.byte_order_name(order) +
              " " +
              woName +
              "] = " +
              unsigned32_str(v),
            )
          }
        }
        None => println(ty + " bytes must be two-digit hex")
      }
      return
    }
    println(ty + " decode needs 2 words or 4 bytes")
    return
  }
  if ty == "int16" || ty == "uint16" {
    if tokens.length() == 1 {
      match parse_hex_n(tokens[0], 4) {
        Some(w) => {
          let wval = w & 0xFFFF
          if ty == "int16" {
            println(
              "int16 0x" +
              tokens[0] +
              " = " +
              @modbus_lint.decode_int16(wval).to_string(),
            )
          } else {
            println(
              "uint16 0x" +
              tokens[0] +
              " = " +
              @modbus_lint.decode_uint16(wval).to_string(),
            )
          }
        }
        None => println("bad " + ty + " word (need 4 hex digits)")
      }
    } else if tokens.length() == 2 {
      // Two two-digit tokens are read as a raw wire byte pair.
      match parse_hex_bytes(tokens) {
        Some(bs) => {
          let wval = @modbus_lint.int16_from_bytes(bs, order) & 0xFFFF
          if ty == "int16" {
            println(
              "int16 [" +
              @modbus_lint.byte_order_name(order) +
              "] = " +
              @modbus_lint.decode_int16(wval).to_string(),
            )
          } else {
            println(
              "uint16 [" +
              @modbus_lint.byte_order_name(order) +
              "] = " +
              @modbus_lint.decode_uint16(wval).to_string(),
            )
          }
        }
        None => println(ty + " bytes must be two-digit hex")
      }
    } else {
      println(ty + " decode needs 1 word or 2 bytes")
    }
    return
  }
  println("unknown type: " + ty + " (expected float32|float64|int32|uint32)")
}

///|
/// Join the leftover (non-flag) arguments into a single point-table line. The
/// tokens are re-joined with a single space so that a register line the shell
/// split on whitespace (e.g. `a 40001 int16 R`) is reconstructed correctly.
fn join_lines(lines : Array[String]) -> String {
  let mut out = ""
  for t in lines {
    if out.length() > 0 {
      out = out + " "
    }
    out = out + t
  }
  out
}

///|
/// Parse, optionally sort-and-show, then lint and print the device.
fn run_device(
  parsed : Result[@modbus_lint.Device, String],
  fmt : OutputFormat,
  gap_opt : Int?,
  show : Bool,
  want_stats : Bool,
) -> Unit {
  let dev = match parsed {
    Err(e) => {
      println("parse error: " + e)
      return
    }
    Ok(d) => d
  }
  if want_stats {
    println("=== point-table statistics ===")
    println(@modbus_lint.stats_text(dev))
    return
  }
  if show {
    print_table(@modbus_lint.sort_by_address(dev))
  }
  let issues = match gap_opt {
    Some(n) => @modbus_lint.lint_with_gap(dev, n)
    None => @modbus_lint.lint(dev)
  }
  let out = match fmt {
    Text => @modbus_lint.render(issues)
    Json => @modbus_lint.render_json(issues)
    Markdown => @modbus_lint.render_markdown(issues)
    Summary => @modbus_lint.render_summary(dev, issues)
    Csv => @modbus_lint.render_csv(issues)
    Html => @modbus_lint.render_html(issues)
  }
  println(out)
}

///|
/// Print a point table, sorted by address, as a small aligned text table.
fn print_table(dev : @modbus_lint.Device) -> Unit {
  println("name          address type   access unit jsonb")
  for r in dev.registers {
    println(
      @modbus_lint.pad(r.name) +
      " " +
      @modbus_lint.pad_num(r.address) +
      " " +
      @modbus_lint.pad(@modbus_lint.type_name(r.rtype)) +
      " " +
      @modbus_lint.pad(@modbus_lint.access_name(r.access)) +
      " " +
      r.unit +
      " " +
      r.jsonb,
    )
  }
  println("")
}

///|
/// A small demo table that intentionally contains one address overlap so the
/// linter output is easy to see.
fn example_text() -> String {
  "# example point table - demo (contains one intentional overlap)\n" +
  "coil_temp   40001 float32 R  degC  jsonb->coil_temp\n" +
  "conveyor    40003 bool    RW        jsonb->conveyor_run\n" +
  "tank_level  40004 uint16  R   mm   jsonb->tank_level\n" +
  "spray_prs   40005 uint16  R   kPa  jsonb->spray_press\n" +
  "big_val     40010 float32 R         jsonb->big_val\n" +
  "small_val   40011 int16   R         jsonb->small_val\n"
}
