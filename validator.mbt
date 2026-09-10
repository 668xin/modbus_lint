// Validator: apply Modbus point-table lint rules to a parsed Device.
//
// Rules:
//   1. Register names must be unique.
//   2. Addresses must fall inside a standard Modbus area (1..49999).
//   3. A multi-word register must not span past the end of its area.
//   4. Two registers in the same area must not overlap in address space
//      (accounting for the word count of each type).
//   5. A non-empty jsonb field should be a plain identifier (warning).

///|
/// Run every rule and return all findings.
pub fn lint(dev : Device) -> Array[Issue] {
  let issues : Array[Issue] = []
  let regs = dev.registers

  // Rule 1: duplicate names.
  for i = 0; i < regs.length(); i = i + 1 {
    for j = i + 1; j < regs.length(); j = j + 1 {
      if regs[i].name == regs[j].name {
        issues.push(
          mk_issue(
            Error,
            regs[j].line,
            "duplicate register name '" +
            regs[j].name +
            "' (first defined at line " +
            regs[i].line.to_string() +
            ")",
          ),
        )
      }
    }
  }

  // Rules 2-4: address range and overlap.
  for i = 0; i < regs.length(); i = i + 1 {
    let a = regs[i]
    let area = area_of(a.address)
    if area < 0 {
      issues.push(
        mk_issue(
          Error,
          a.line,
          "address " +
          a.address.to_string() +
          " is outside any standard Modbus area (coils 1-9999, DI 10001-19999, IR 30001-39999, HR 40001-49999)",
        ),
      )
      continue
    }
    let (lo, hi) = local_range(a.address, a.rtype)
    if hi > 9999 {
      issues.push(
        mk_issue(
          Error,
          a.line,
          "register '" +
          a.name +
          "' spans past the end of its Modbus area (local " +
          lo.to_string() +
          ".." +
          hi.to_string() +
          ", max 9999)",
        ),
      )
    }
    for j = 0; j < regs.length(); j = j + 1 {
      if j == i {
        continue
      }
      let b = regs[j]
      if area_of(b.address) != area {
        continue
      }
      let (lo2, hi2) = local_range(b.address, b.rtype)
      if hi < lo2 || hi2 < lo {
        // disjoint, ok
      } else {
        issues.push(
          mk_issue(
            Error,
            a.line,
            "register '" +
            a.name +
            "' (local " +
            lo.to_string() +
            ".." +
            hi.to_string() +
            ") overlaps '" +
            b.name +
            "' (local " +
            lo2.to_string() +
            ".." +
            hi2.to_string() +
            ")",
          ),
        )
      }
    }
  }

  // Rule 5: jsonb field sanity (parsed path: non-empty values must start with
  // "jsonb->" and contain only valid dotted identifier segments).
  for r in regs {
    if !jsonb_is_unset(r.jsonb) {
      match parse_jsonb_path(r.jsonb) {
        Err(e) =>
          issues.push(
            mk_issue(
              Warning,
              r.line,
              "register '" + r.name + "' has an invalid jsonb field: " + e,
            ),
          )
        Ok(_) => ()
      }
    }
  }

  // Rule 6: 地址间隙过大，可能漏配或地址笔误（Warning）。
  for i = 0; i < regs.length(); i = i + 1 {
    let a = regs[i]
    let area = area_of(a.address)
    if area < 0 {
      continue
    }
    // hi = 该寄存器占用的最后一个本地地址
    let hi = a.address - area_base(area) + word_count(a.rtype)
    let mut next_lo = -1
    for j = 0; j < regs.length(); j = j + 1 {
      if j == i {
        continue
      }
      let b = regs[j]
      if area_of(b.address) != area {
        continue
      }
      let lo2 = b.address - area_base(area) + 1
      if lo2 > hi {
        if next_lo < 0 || lo2 < next_lo {
          next_lo = lo2
        }
      }
    }
    if next_lo > 0 {
      let gap = next_lo - hi - 1
      if gap > max_gap() {
        issues.push(
          mk_issue(
            Warning,
            a.line,
            "register '" +
            a.name +
            "' 与下一个寄存器之间有 " +
            gap.to_string() +
            " 字地址间隙（阈值 " +
            max_gap().to_string() +
            "），可能存在漏配或地址笔误",
          ),
        )
      }
    }
  }

  // Rule 7: 多个寄存器映射到同一个 JSONB 字段，采集时会互相覆盖（Warning）。
  for i = 0; i < regs.length(); i = i + 1 {
    if regs[i].jsonb.length() == 0 {
      continue
    }
    for j = i + 1; j < regs.length(); j = j + 1 {
      if regs[i].jsonb == regs[j].jsonb {
        issues.push(
          mk_issue(
            Warning,
            regs[j].line,
            "register '" +
            regs[j].name +
            "' 与 '" +
            regs[i].name +
            "' 映射到同一个 JSONB 字段 '" +
            regs[j].jsonb +
            "'，采集时会互相覆盖",
          ),
        )
      }
    }
  }

  // Rule 8: register name sanity (empty name is an error; odd characters warn).
  for r in regs {
    if r.name.length() == 0 {
      issues.push(mk_issue(Error, r.line, "register with an empty name"))
    } else if !valid_name(r.name) {
      issues.push(
        mk_issue(
          Warning,
          r.line,
          "register name '" +
          r.name +
          "' contains characters outside [A-Za-z0-9_.-]",
        ),
      )
    }
  }

  // Rule 9: a multi-word type used at a bit-addressed location (coils / DI).
  for r in regs {
    let ar = area_of(r.address)
    if area_is_bit(ar) && word_count(r.rtype) > 1 {
      issues.push(
        mk_issue(
          Warning,
          r.line,
          "register '" +
          r.name +
          "' uses multi-word type " +
          type_name(r.rtype) +
          " in a bit-addressed area (" +
          area_name(ar) +
          ")",
        ),
      )
    }
  }

  // Rule 10: write access on an input-only area (DI / IR).
  for r in regs {
    let ar = area_of(r.address)
    let writable = match r.access {
      Write => true
      ReadWrite => true
      _ => false
    }
    if area_is_input(ar) && writable {
      issues.push(
        mk_issue(
          Warning,
          r.line,
          "register '" +
          r.name +
          "' is declared " +
          access_name(r.access) +
          " but lives in an input area (" +
          area_name(ar) +
          ")",
        ),
      )
    }
  }

  // Rule 11: names that differ only by letter case are easy to mis-use.
  for i = 0; i < regs.length(); i = i + 1 {
    for j = i + 1; j < regs.length(); j = j + 1 {
      let ni = lowercase(regs[i].name)
      let nj = lowercase(regs[j].name)
      if ni != "" && ni == nj && regs[i].name != regs[j].name {
        issues.push(
          mk_issue(
            Warning,
            regs[j].line,
            "register name '" +
            regs[j].name +
            "' differs from '" +
            regs[i].name +
            "' only by case",
          ),
        )
      }
    }
  }

  issues
}

///|
/// 允许的最大地址间隙（字）；超过则提示可能漏配。
fn max_gap() -> Int {
  16
}

///|
/// True when every character of `s` is one of A-Za-z0-9_.- (used for names).
fn valid_name(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '.' ||
      c == '-'
    if !ok {
      return false
    }
  }
  true
}

///|
/// ASCII lower-casing helper (used by the case-duplicate rule).
fn lowercase(s : String) -> String {
  let out = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    if c >= 'A' && c <= 'Z' {
      let low = c.to_int() + 32
      out.write_char(low.unsafe_to_char())
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Convert an address + type into its [low, high] local-word range (1-based).
fn local_range(addr : Int, rtype : RegisterType) -> (Int, Int) {
  let base = area_base(area_of(addr))
  let lo = addr - base + 1
  let hi = lo + word_count(rtype) - 1
  (lo, hi)
}

///|
test "lint flags an overlap between a float32 and an int16" {
  let r1 = {
    name: "a",
    address: 40001,
    rtype: TFloat32,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  let r2 = {
    name: "b",
    address: 40002,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 2,
  }
  assert_eq(lint({ registers: [r1, r2], }).length() > 0, true)
}

///|
test "lint passes disjoint registers" {
  let r1 = {
    name: "a",
    address: 40001,
    rtype: TFloat32,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  let r2 = {
    name: "b",
    address: 40003,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 2,
  }
  assert_eq(lint({ registers: [r1, r2], }).length(), 0)
}

///|
test "lint flags duplicate names" {
  let r1 = {
    name: "x",
    address: 40001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  let r2 = {
    name: "x",
    address: 40003,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 2,
  }
  assert_eq(lint({ registers: [r1, r2], }).length() > 0, true)
}

///|
test "lint flags out-of-range address" {
  let r = {
    name: "x",
    address: 50001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  assert_eq(lint({ registers: [r], }).length() > 0, true)
}

///|
test "lint accepts a float64 that fits exactly at the boundary" {
  let r = {
    name: "x",
    address: 49996,
    rtype: TFloat64,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  assert_eq(lint({ registers: [r], }).length(), 0)
}

///|
test "lint flags a float64 that overflows the area" {
  let r = {
    name: "x",
    address: 49998,
    rtype: TFloat64,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  assert_eq(lint({ registers: [r], }).length() > 0, true)
}

///|
test "lint warns about a large address gap" {
  // 40001 之后直接跳到 40050，中间 48 字没有任何点，应提示漏配
  let r1 = {
    name: "a",
    address: 40001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "jsonb->a",
    line: 1,
  }
  let r2 = {
    name: "b",
    address: 40050,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "jsonb->b",
    line: 2,
  }
  assert_eq(lint({ registers: [r1, r2], }).length() > 0, true)
}

///|
test "lint does not warn about a small address gap" {
  let r1 = {
    name: "a",
    address: 40001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "jsonb->a",
    line: 1,
  }
  let r2 = {
    name: "b",
    address: 40005,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "jsonb->b",
    line: 2,
  }
  assert_eq(lint({ registers: [r1, r2], }).length(), 0)
}

///|
test "lint warns when two registers share one jsonb field" {
  let r1 = {
    name: "a",
    address: 40001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "jsonb->same",
    line: 1,
  }
  let r2 = {
    name: "b",
    address: 40002,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "jsonb->same",
    line: 2,
  }
  assert_eq(lint({ registers: [r1, r2], }).length() > 0, true)
}

///|
test "lint flags an empty register name and warns on odd name characters" {
  let r1 = {
    name: "",
    address: 40001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  let r2 = {
    name: "bad name!",
    address: 40002,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 2,
  }
  assert_eq(lint({ registers: [r1, r2], }).length(), 2)
}

///|
test "lint accepts a well-formed name" {
  let r = {
    name: "Temp_1.ok",
    address: 40001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  assert_eq(lint({ registers: [r], }).length(), 0)
}

///|
test "lint warns about a multi-word type in a bit-addressed area" {
  let r = {
    name: "x",
    address: 1001, // coils area
    rtype: TFloat32,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  assert_eq(lint({ registers: [r], }).length() > 0, true)
}

///|
test "lint warns about write access on an input area" {
  let r = {
    name: "x",
    address: 10001, // discrete inputs area
    rtype: TBit,
    access: ReadWrite,
    unit: "",
    jsonb: "",
    line: 1,
  }
  assert_eq(lint({ registers: [r], }).length() > 0, true)
}

///|
test "lint flags names that differ only by case" {
  let r1 = {
    name: "temp",
    address: 40001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  let r2 = {
    name: "TEMP",
    address: 40002,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 2,
  }
  assert_eq(lint({ registers: [r1, r2], }).length() > 0, true)
}

///|
test "lint warns on an invalid jsonb path" {
  let r = {
    name: "x",
    address: 40001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "jsonb->a b",
    line: 1,
  }
  assert_eq(lint({ registers: [r], }).length() > 0, true)
}

///|
test "lint accepts an empty jsonb path" {
  let r = {
    name: "x",
    address: 40001,
    rtype: TInt16,
    access: Read,
    unit: "",
    jsonb: "",
    line: 1,
  }
  assert_eq(lint({ registers: [r], }).length(), 0)
}
