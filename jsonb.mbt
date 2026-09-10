// JsonB paths: parse and validate the `jsonb->a.b.c` field syntax used in point
// tables, and expose helpers for validation rules and stats.
//
// A JsonB field names the key (and optional dotted sub-keys) under which a
// register is exposed by the data-acquisition pipeline. Keeping a real parser
// here lets the validator give precise diagnostics and lets stats/tools reuse
// the same notion of "path segment".

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_alnum(c : Char) -> Bool {
  is_alpha(c) || is_digit(c)
}

///|
fn is_segment(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    if !(is_alnum(c) || c == '_') {
      return false
    }
  }
  true
}

///|
fn starts_with(s : String, prefix : String) -> Bool {
  if s.length() < prefix.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if s[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
/// True when the raw field uses the JsonB prefix `jsonb->`.
pub fn is_jsonb_prefixed(s : String) -> Bool {
  starts_with(s, "jsonb->")
}

///|
/// True when the raw jsonb string is effectively empty / unused.
pub fn jsonb_is_unset(s : String) -> Bool {
  s.length() == 0
}

///|
/// Parse a jsonb field into its dotted segments that follow the `jsonb->`
/// prefix. Returns `Err` with a human message when the value is empty, lacks the
/// prefix, an empty segment appears, or a segment contains an invalid character.
pub fn parse_jsonb_path(s : String) -> Result[Array[String], String] {
  if s.length() == 0 {
    return Err("empty jsonb value")
  }
  if !is_jsonb_prefixed(s) {
    return Err("missing 'jsonb->' prefix")
  }
  let segs : Array[String] = []
  let mut cur = StringBuilder()
  for i = 7; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    if c == '.' {
      let seg = cur.to_string()
      if seg == "" || !is_segment(seg) {
        return Err("invalid segment '" + seg + "'")
      }
      segs.push(seg)
      cur = StringBuilder()
    } else {
      cur.write_char(c)
    }
  }
  let last = cur.to_string()
  if last == "" || !is_segment(last) {
    return Err("invalid segment '" + last + "'")
  }
  segs.push(last)
  if segs.length() == 0 {
    return Err("empty jsonb path")
  }
  Ok(segs)
}

///|
/// The number of segments in a parseable jsonb path (or 0 when unparseable).
pub fn jsonb_depth(s : String) -> Int {
  match parse_jsonb_path(s) {
    Ok(segs) => segs.length()
    Err(_) => 0
  }
}

///|
/// The final (leaf) segment of a jsonb path, used for naming hints.
pub fn jsonb_leaf(s : String) -> String {
  match parse_jsonb_path(s) {
    Ok(segs) => segs[segs.length() - 1]
    Err(_) => s
  }
}

///|
test "parse_jsonb_path accepts a simple path" {
  match parse_jsonb_path("jsonb->coil_temp") {
    Ok(segs) => {
      assert_eq(segs.length(), 1)
      assert_eq(segs[0], "coil_temp")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "parse_jsonb_path accepts a dotted path" {
  match parse_jsonb_path("jsonb->plant.line.temp") {
    Ok(segs) => assert_eq(segs.length(), 3)
    Err(_) => assert_true(false)
  }
}

///|
test "parse_jsonb_path rejects empty and unprefixed values" {
  assert_eq(parse_jsonb_path("") is Ok(_), false)
  assert_eq(parse_jsonb_path("coil_temp") is Ok(_), false)
  assert_eq(parse_jsonb_path("jsonb->") is Ok(_), false)
}

///|
test "parse_jsonb_path rejects empty or invalid segments" {
  assert_eq(parse_jsonb_path("jsonb->a..b") is Ok(_), false)
  assert_eq(parse_jsonb_path("jsonb->a b") is Ok(_), false)
  assert_eq(parse_jsonb_path("jsonb->a!b") is Ok(_), false)
  assert_eq(parse_jsonb_path("jsonb->.a") is Ok(_), false)
}

///|
test "jsonb_depth and jsonb_leaf" {
  assert_eq(jsonb_depth("jsonb->a.b.c"), 3)
  assert_eq(jsonb_depth("garbage"), 0)
  assert_eq(jsonb_leaf("jsonb->line.temp"), "temp")
  assert_eq(jsonb_leaf("jsonb->x"), "x")
  assert_eq(jsonb_leaf(""), "")
}
