// JSON I/O: serialize a Device (or lint Issues) to JSON and back.
//
// Conversion uses `moonbitlang/core/json`. To keep the JSON schema aligned with
// the point-table text keywords ("float32", "R", "error", ...) and to stay
// warning-free under nightly `moon check --deny-warn`, we do NOT derive
// ToJson/FromJson on any custom type (doing so triggers the
// `implicit_impl_as_method` deprecation warning). Instead we build/read plain
// `Map[String, Json]` / arrays / primitives using only the standard ToJson and
// FromJson impls that ship with core.

///|
/// Build the JSON object for a single register using only standard ToJson impls.
fn reg_to_map(r : Register) -> Map[String, Json] {
  {
    "name": @json.to_json(r.name),
    "address": @json.to_json(r.address),
    "rtype": @json.to_json(type_name(r.rtype)),
    "access": @json.to_json(access_name(r.access)),
    "unit": @json.to_json(r.unit),
    "jsonb": @json.to_json(r.jsonb),
    "line": @json.to_json(r.line),
  }
}

///|
/// Serialize a whole `Device` to a `Json` value.
pub fn device_to_json(dev : Device) -> Json {
  let rows : Array[Map[String, Json]] = []
  for r in dev.registers {
    rows.push(reg_to_map(r))
  }
  @json.to_json({ "registers": @json.to_json(rows) })
}

///|
/// Serialize a whole `Device` to a pretty JSON string.
pub fn device_to_json_string(dev : Device) -> String {
  device_to_json(dev).stringify(indent=2)
}

///|
/// Read a required string field from a decoded object.
fn jstr(row : Map[String, Json], key : String) -> Result[String, String] {
  match row.get(key) {
    None => Err("missing field '" + key + "'")
    Some(v) => {
      let s : String = @json.from_json(v) catch {
        _ => return Err("field '" + key + "' must be a string")
      }
      Ok(s)
    }
  }
}

///|
/// Read a required int field from a decoded object.
fn jint(row : Map[String, Json], key : String) -> Result[Int, String] {
  match row.get(key) {
    None => Err("missing field '" + key + "'")
    Some(v) => {
      let n : Int = @json.from_json(v) catch {
        _ => return Err("field '" + key + "' must be an integer")
      }
      Ok(n)
    }
  }
}

///|
/// Convert a decoded object back to a `Register`, validating the keywords.
fn reg_from_map(row : Map[String, Json]) -> Result[Register, String] {
  let name = match jstr(row, "name") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let address = match jint(row, "address") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let unit = match jstr(row, "unit") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let jsonb = match jstr(row, "jsonb") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let line = match jint(row, "line") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let rtype_key = match jstr(row, "rtype") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let access_key = match jstr(row, "access") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let rtype = match parse_type(rtype_key) {
    Ok(v) => v
    Err(e) => return Err("invalid 'rtype': " + e)
  }
  let access = match parse_access(access_key) {
    Ok(v) => v
    Err(e) => return Err("invalid 'access': " + e)
  }
  Ok({ name, address, rtype, access, unit, jsonb, line, })
}

///|
/// Parse a JSON string back into a `Device`.
pub fn parse_device_json(text : String) -> Result[Device, String] {
  let j = @json.parse(text) catch { _ => return Err("invalid JSON document") }
  let obj : Map[String, Json] = @json.from_json(j) catch {
    _ => return Err("top level must be a JSON object")
  }
  let regsJson = match obj.get("registers") {
    None => return Err("missing field 'registers'")
    Some(v) => v
  }
  let rows : Array[Map[String, Json]] = @json.from_json(regsJson) catch {
    _ => return Err("field 'registers' must be an array of objects")
  }
  let regs : Array[Register] = []
  for row in rows {
    match reg_from_map(row) {
      Ok(r) => regs.push(r)
      Err(e) => return Err(e)
    }
  }
  Ok({ registers: regs, })
}

///|
/// Serialize a lint finding to its JSON object form.
fn issue_to_map(it : Issue) -> Map[String, Json] {
  {
    "severity": @json.to_json(severity_name(it.severity)),
    "line": @json.to_json(it.line),
    "message": @json.to_json(it.message),
  }
}

///|
/// Render lint findings as a JSON array string.
pub fn render_issues_json(issues : Array[Issue]) -> String {
  let rows : Array[Map[String, Json]] = []
  for it in issues {
    rows.push(issue_to_map(it))
  }
  @json.to_json(rows).stringify(indent=2)
}

///|
/// Round-trip a `Device` through JSON.
pub fn json_roundtrip(dev : Device) -> Result[Device, String] {
  parse_device_json(device_to_json_string(dev))
}

///|
test "device json keywords survive a JSON round trip" {
  let dev : Device = {
    registers: [
      {
        name: "coil_temp",
        address: 40001,
        rtype: TFloat32,
        access: Read,
        unit: "degC",
        jsonb: "jsonb->coil_temp",
        line: 2,
      },
      {
        name: "conveyor",
        address: 40003,
        rtype: TBit,
        access: ReadWrite,
        unit: "",
        jsonb: "jsonb->conveyor_run",
        line: 3,
      },
    ],
  }
  let back = json_roundtrip(dev).unwrap()
  assert_eq(back.registers.length(), 2)
  assert_eq(type_name(back.registers[0].rtype), "float32")
  assert_eq(access_name(back.registers[0].access), "R")
  assert_eq(type_name(back.registers[1].rtype), "bool")
  assert_eq(access_name(back.registers[1].access), "RW")
  assert_eq(back.registers[0].unit, "degC")
  assert_eq(back.registers[0].jsonb, "jsonb->coil_temp")
}

///|
test "device json string mentions the text keywords" {
  let dev : Device = {
    registers: [
      {
        name: "a",
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "",
        line: 1,
      },
    ],
  }
  let s = device_to_json_string(dev)
  assert_eq(@json.valid(s), true)
  assert_eq(s.contains("int16"), true)
  assert_eq(s.contains("\"R\""), true)
  assert_eq(s.contains("40001"), true)
}

///|
test "parse_device_json rejects malformed input" {
  assert_eq(parse_device_json("not json") is Ok(_), false)
  assert_eq(parse_device_json("[]") is Ok(_), false)
  assert_eq(parse_device_json("{\"name\": 1}") is Ok(_), false)
}

///|
test "parse_device_json rejects invalid keywords" {
  let bad = "{\"registers\": [{\"name\":\"x\",\"address\":40001,\"rtype\":\"garbage\",\"access\":\"R\",\"unit\":\"\",\"jsonb\":\"\",\"line\":1}]}"
  assert_eq(parse_device_json(bad) is Ok(_), false)
}

///|
test "render_issues_json is valid json with severity keywords" {
  let issues = [mk_issue(Error, 3, "dup name"), mk_issue(Warning, 9, "gap")]
  let s = render_issues_json(issues)
  assert_eq(@json.valid(s), true)
  assert_eq(s.contains("error"), true)
  assert_eq(s.contains("warning"), true)
}

///|
test "parse_device_json accepts an empty register list" {
  assert_eq(parse_device_json("{\"registers\": []}") is Ok(_), true)
}

///|
test "parse_device_json rejects an unknown access keyword" {
  let bad = "{\"registers\": [{\"name\":\"x\",\"address\":40001,\"rtype\":\"int16\",\"access\":\"RR\",\"unit\":\"\",\"jsonb\":\"\",\"line\":1}]}"
  assert_eq(parse_device_json(bad) is Ok(_), false)
}

///|
test "parse_device_json rejects a missing required field" {
  let bad = "{\"registers\": [{\"address\":40001,\"rtype\":\"int16\"}]}"
  assert_eq(parse_device_json(bad) is Ok(_), false)
}

///|
test "parse_device_json tolerates unknown extra fields" {
  let json = "{\"registers\":[{\"name\":\"x\",\"address\":40001,\"rtype\":\"int16\",\"access\":\"R\",\"unit\":\"\",\"jsonb\":\"\",\"line\":1,\"extra\":99}]}"
  let res = parse_device_json(json)
  assert_eq(res is Ok(_), true)
  assert_eq(res.unwrap().registers.length(), 1)
}

///|
test "device json round trip preserves an empty device" {
  let dev : Device = { registers: [], }
  let back = json_roundtrip(dev).unwrap()
  assert_eq(back.registers.length(), 0)
}
