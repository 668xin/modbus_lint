// modbus_lint — a small Modbus point-table linter written in MoonBit.
//
// This file holds the shared data model and pure helper functions used by the
// parser, validator and reporter. Everything here is side-effect free so it is
// easy to unit test.

///|
/// Register data types we understand. Word count follows the Modbus convention
/// (1 word = 2 bytes = 16 bits).
pub enum RegisterType {
  TBit // single coil / discrete input
  TInt16
  TUInt16
  TInt32 // 2 words
  TUInt32 // 2 words
  TFloat32 // 2 words
  TFloat64 // 4 words
}

///|
/// Access mode of a register.
pub enum Access {
  Read
  Write
  ReadWrite
}

///|
/// Severity of a lint finding.
pub enum Severity {
  Error
  Warning
}

///|
/// A single lint finding.
pub struct Issue {
  severity : Severity
  line : Int
  message : String
}

///|
/// A single register described in a point table.
pub struct Register {
  name : String
  address : Int
  rtype : RegisterType
  access : Access
  unit : String
  jsonb : String
  line : Int
}

///|
/// A parsed device: an ordered list of registers.
pub struct Device {
  registers : Array[Register]
}

///|
/// Number of 16-bit words a register type occupies.
pub fn word_count(rtype : RegisterType) -> Int {
  match rtype {
    TBit => 1
    TInt16 => 1
    TUInt16 => 1
    TInt32 => 2
    TUInt32 => 2
    TFloat32 => 2
    TFloat64 => 4
  }
}

///|
/// Map a 1-based Modbus address to its area id.
///   0 = coils (1..9999), 1 = discrete inputs (10001..19999),
///   3 = input registers (30001..39999), 4 = holding registers (40001..49999).
/// Returns -1 when the address is outside any standard area.
fn area_of(addr : Int) -> Int {
  if addr >= 40001 && addr <= 49999 {
    4
  } else if addr >= 30001 && addr <= 39999 {
    3
  } else if addr >= 10001 && addr <= 19999 {
    1
  } else if addr >= 1 && addr <= 9999 {
    0
  } else {
    -1
  }
}

///|
/// First address of the area that `area_of` returns (-1 -> 0).
fn area_base(area : Int) -> Int {
  match area {
    0 => 1
    1 => 10001
    3 => 30001
    4 => 40001
    _ => 0
  }
}

///|
/// Human-readable name of an area id (see `area_of`).
pub fn area_name(area : Int) -> String {
  match area {
    0 => "coils"
    1 => "discrete inputs"
    3 => "input registers"
    4 => "holding registers"
    _ => "outside any standard area"
  }
}

///|
/// True when the area holds inputs only (discrete inputs / input registers).
pub fn area_is_input(area : Int) -> Bool {
  area == 1 || area == 3
}

///|
/// True when the area is bit-addressable (coils / discrete inputs).
pub fn area_is_bit(area : Int) -> Bool {
  area == 0 || area == 1
}

///|
/// Parse a non-negative / signed decimal integer without relying on stdlib
/// number parsing, so the behaviour is predictable across targets.
fn parse_int(s : String) -> Result[Int, String] {
  if s.length() == 0 {
    return Err("empty number")
  }
  let neg = s[0] == '-'
  let start = if neg { 1 } else { 0 }
  if neg && s.length() == 1 {
    return Err("invalid number: " + s)
  }
  let mut v = 0
  let zero = '0'.to_int()
  for i = start; i < s.length(); i = i + 1 {
    let c = s[i]
    if c < '0' || c > '9' {
      return Err("not a number: " + s)
    }
    v = v * 10 + (c.to_int() - zero)
  }
  if neg {
    v = -v
  }
  Ok(v)
}

///|
/// Parse a register type keyword.
fn parse_type(s : String) -> Result[RegisterType, String] {
  if s == "bool" {
    Ok(TBit)
  } else if s == "int16" {
    Ok(TInt16)
  } else if s == "uint16" {
    Ok(TUInt16)
  } else if s == "int32" {
    Ok(TInt32)
  } else if s == "uint32" {
    Ok(TUInt32)
  } else if s == "float32" {
    Ok(TFloat32)
  } else if s == "float64" {
    Ok(TFloat64)
  } else {
    Err(
      "unknown type: " +
      s +
      " (want bool|int16|uint16|int32|uint32|float32|float64)",
    )
  }
}

///|
/// Parse an access keyword.
fn parse_access(s : String) -> Result[Access, String] {
  if s == "R" {
    Ok(Read)
  } else if s == "W" {
    Ok(Write)
  } else if s == "RW" {
    Ok(ReadWrite)
  } else {
    Err("unknown access: " + s + " (want R|W|RW)")
  }
}

///|
/// True when `s` is a usable JSONB field path such as `jsonb->coil_temp`.
fn is_ident(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-' ||
      c == '.' ||
      c == '>'
    if !ok {
      return false
    }
  }
  true
}

///|
/// Convenience constructor for an Issue.
fn mk_issue(sev : Severity, line : Int, message : String) -> Issue {
  { severity: sev, line, message, }
}

///|
/// Human-readable keyword for a register type, symmetric with `parse_type`.
pub fn type_name(rtype : RegisterType) -> String {
  match rtype {
    TBit => "bool"
    TInt16 => "int16"
    TUInt16 => "uint16"
    TInt32 => "int32"
    TUInt32 => "uint32"
    TFloat32 => "float32"
    TFloat64 => "float64"
  }
}

///|
/// Keyword for an access mode, symmetric with `parse_access`.
pub fn access_name(access : Access) -> String {
  match access {
    Read => "R"
    Write => "W"
    ReadWrite => "RW"
  }
}

///|
/// Lower-case name of a severity, used in JSON reports.
pub fn severity_name(sev : Severity) -> String {
  match sev {
    Error => "error"
    Warning => "warning"
  }
}

///|
/// Split text into lines, tolerating CRLF, preserving order so the returned
/// index (plus one) matches the file line number.
fn split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    if c == '\n' {
      out.push(cur.to_string())
      cur = StringBuilder()
    } else if c != '\r' {
      cur.write_char(c)
    }
  }
  out.push(cur.to_string())
  out
}

///|
/// Split a line on runs of whitespace, dropping empty tokens.
fn split_ws(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' {
      if !cur.is_empty() {
        out.push(cur.to_string())
        cur = StringBuilder()
      }
    } else {
      cur.write_char(c)
    }
  }
  if !cur.is_empty() {
    out.push(cur.to_string())
  }
  out
}

///|
test "word_count matches Modbus convention" {
  assert_eq(word_count(TBit), 1)
  assert_eq(word_count(TInt16), 1)
  assert_eq(word_count(TFloat32), 2)
  assert_eq(word_count(TFloat64), 4)
}

///|
test "area_of classifies standard Modbus addresses" {
  assert_eq(area_of(40001), 4)
  assert_eq(area_of(30001), 3)
  assert_eq(area_of(10001), 1)
  assert_eq(area_of(1), 0)
  assert_eq(area_of(50001), -1)
  assert_eq(area_of(25000), -1)
}

///|
test "parse_int handles signs and rejects garbage" {
  assert_eq(parse_int("123").unwrap(), 123)
  assert_eq(parse_int("-7").unwrap(), -7)
  assert_eq(parse_int("") is Ok(_), false)
  assert_eq(parse_int("12x") is Ok(_), false)
}

///|
test "is_ident accepts dotted and dashed names" {
  assert_eq(is_ident("jsonb->coil_temp"), true)
  assert_eq(is_ident(""), false)
  assert_eq(is_ident("bad name"), false)
}
