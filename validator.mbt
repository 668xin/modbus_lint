// Validator: apply Modbus point-table lint rules to a parsed Device.
//
// Rules:
//   1. Register names must be unique.
//   2. Addresses must fall inside a standard Modbus area (1..49999).
//   3. A multi-word register must not span past the end of its area.
//   4. Two registers in the same area must not overlap in address space
//      (accounting for the word count of each type).
//   5. A non-empty jsonb field should be a plain identifier (warning).

/// Run every rule and return all findings.
pub fn lint(dev : Device) -> Array[Issue] {
  let mut issues : Array[Issue] = []
  let regs = dev.registers

  // Rule 1: duplicate names.
  for i = 0; i < regs.length(); i = i + 1 {
    for j = i + 1; j < regs.length(); j = j + 1 {
      if regs[i].name == regs[j].name {
        issues.push(
          mk_issue(
            Error,
            regs[j].line,
            "duplicate register name '"
            + regs[j].name
            + "' (first defined at line "
            + regs[i].line.to_string()
            + ")",
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
          "address "
          + a.address.to_string()
          + " is outside any standard Modbus area (coils 1-9999, DI 10001-19999, IR 30001-39999, HR 40001-49999)",
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
          "register '"
          + a.name
          + "' spans past the end of its Modbus area (local "
          + lo.to_string()
          + ".."
          + hi.to_string()
          + ", max 9999)",
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
            "register '"
            + a.name
            + "' (local "
            + lo.to_string()
            + ".."
            + hi.to_string()
            + ") overlaps '"
            + b.name
            + "' (local "
            + lo2.to_string()
            + ".."
            + hi2.to_string()
            + ")",
          ),
        )
      }
    }
  }

  // Rule 5: jsonb field sanity.
  for r in regs {
    if r.jsonb.length() > 0 && !is_ident(r.jsonb) {
      issues.push(
        mk_issue(
          Warning,
          r.line,
          "jsonb field '"
          + r.jsonb
          + "' is not a plain identifier (expected e.g. jsonb->coil_temp)",
        ),
      )
    }
  }

  issues
}

/// Convert an address + type into its [low, high] local-word range (1-based).
fn local_range(addr : Int, rtype : RegisterType) -> (Int, Int) {
  let base = area_base(area_of(addr))
  let lo = addr - base + 1
  let hi = lo + word_count(rtype) - 1
  (lo, hi)
}

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
  assert_eq(lint({ registers: [r1, r2] }).length() > 0, true)
}

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
  assert_eq(lint({ registers: [r1, r2] }).length(), 0)
}

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
  assert_eq(lint({ registers: [r1, r2] }).length() > 0, true)
}

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
  assert_eq(lint({ registers: [r] }).length() > 0, true)
}

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
  assert_eq(lint({ registers: [r] }).length(), 0)
}

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
  assert_eq(lint({ registers: [r] }).length() > 0, true)
}
