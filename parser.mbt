// Parser: turn the line-based point-table text into a Device.
//
// Point table format (one register per line, `#` starts a comment):
//   <name> <address> <type> <access> [<unit>] [<jsonb-field>]
// Example:
//   coil_temp  40001 float32 R  degC  jsonb->coil_temp
//   conveyor   40003 bool    RW        jsonb->conveyor_run
//
// The Modbus area (coil / discrete input / input register / holding register)
// is inferred from the address prefix, so no extra header is required.

/// Parse a whole point-table document.
pub fn parse_device(text : String) -> Result[Device, String] {
  let lines = split_lines(text)
  let mut regs : Array[Register] = []
  for i = 0; i < lines.length(); i = i + 1 {
    let raw = lines[i].trim()
    if raw.length() == 0 {
      continue
    }
    if raw[0] == '#' {
      continue
    }
    let r = parse_line(raw, i + 1)?
    regs.push(r)
  }
  Ok({ registers: regs })
}

/// Parse a single register line.
fn parse_line(line : String, line_no : Int) -> Result[Register, String] {
  let toks = split_ws(line)
  if toks.length() < 4 {
    return Err(
      "line "
      + line_no.to_string()
      + ": expected '<name> <addr> <type> <access> [unit] [jsonb]', got "
      + toks.length().to_string()
      + " field(s)",
    )
  }
  let name = toks[0]
  let addr = match parse_int(toks[1]) {
    Ok(v) => v
    Err(e) => return Err("line " + line_no.to_string() + ": bad address: " + e)
  }
  let rtype = match parse_type(toks[2]) {
    Ok(v) => v
    Err(e) => return Err("line " + line_no.to_string() + ": " + e)
  }
  let access = match parse_access(toks[3]) {
    Ok(v) => v
    Err(e) => return Err("line " + line_no.to_string() + ": " + e)
  }
  let unit = if toks.length() > 4 { toks[4] } else { "" }
  let jsonb = if toks.length() > 5 { toks[5] } else { "" }
  Ok({
    name: name,
    address: addr,
    rtype: rtype,
    access: access,
    unit: unit,
    jsonb: jsonb,
    line: line_no,
  })
}

test "parse_device reads comments and registers" {
  let text =
    "# washer line 1\n"
    + "coil_temp 40001 float32 R degC jsonb->coil_temp\n"
    + "\n"
    + "conveyor  40003 bool RW jsonb->conveyor_run\n"
  let dev = parse_device(text).unwrap()
  assert_eq(dev.registers.length(), 2)
  assert_eq(dev.registers[0].name, "coil_temp")
  assert_eq(dev.registers[1].address, 40003)
}

test "parse_device rejects unknown type" {
  let res = parse_device("x 40001 unknown R")
  assert_eq(res.is_ok(), false)
}

test "parse_device rejects too-few fields" {
  let res = parse_device("x 40001 float32")
  assert_eq(res.is_ok(), false)
}
