// Reporter: render lint findings into a human-readable, copy-pasteable report.

///|
/// Render all findings. Returns a short "OK" message when there are none.
pub fn render(issues : Array[Issue]) -> String {
  if issues.length() == 0 {
    return "OK: no issues found."
  }
  let mut buf = ""
  let mut errs = 0
  let mut warns = 0
  for it in issues {
    match it.severity {
      Error => {
        errs = errs + 1
        buf = buf +
          "[ERROR] line " +
          it.line.to_string() +
          ": " +
          it.message +
          "\n"
      }
      Warning => {
        warns = warns + 1
        buf = buf +
          "[WARN]  line " +
          it.line.to_string() +
          ": " +
          it.message +
          "\n"
      }
    }
  }
  buf +
  "\nsummary: " +
  errs.to_string() +
  " error(s), " +
  warns.to_string() +
  " warning(s)."
}

///|
/// Count findings with Error severity (used to decide a non-zero exit code).
pub fn error_count(issues : Array[Issue]) -> Int {
  let mut n = 0
  for it in issues {
    match it.severity {
      Error => n = n + 1
      Warning => n = n
    }
  }
  n
}

///|
/// 转义 JSON 字符串中的引号与反斜杠。
fn escape(s : String) -> String {
  let out = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int().unsafe_to_char()
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// 以 JSON 数组形式输出，便于 CI 或其他工具消费。
pub fn render_json(issues : Array[Issue]) -> String {
  let mut buf = "[\n"
  for i = 0; i < issues.length(); i = i + 1 {
    let it = issues[i]
    let sev = match it.severity {
      Error => "error"
      Warning => "warning"
    }
    buf = buf +
      "  {\"severity\": \"" +
      sev +
      "\", \"line\": " +
      it.line.to_string() +
      ", \"message\": \"" +
      escape(it.message) +
      "\"}"
    if i + 1 < issues.length() {
      buf = buf + ","
    }
    buf = buf + "\n"
  }
  buf + "]"
}

///|
test "render reports OK when clean" {
  assert_eq(render([]), "OK: no issues found.")
}

///|
test "render counts errors and warnings" {
  let issues = [
    mk_issue(Error, 1, "dup name"),
    mk_issue(Warning, 2, "weird jsonb"),
  ]
  assert_eq(error_count(issues), 1)
  assert_eq(render(issues).length() > 0, true)
  assert_eq(error_count([mk_issue(Warning, 3, "only a warning")]), 0)
}

///|
test "render_json emits one object per finding" {
  let issues = [mk_issue(Error, 7, "dup name")]
  assert_eq(
    render_json(issues),
    "[\n  {\"severity\": \"error\", \"line\": 7, \"message\": \"dup name\"}\n]",
  )
}

///|
test "render_json on empty findings is an empty array" {
  assert_eq(render_json([]), "[\n]")
}

///|
/// Renders the findings as a Markdown table (one row per finding), which is
/// convenient to paste into issue trackers or MR descriptions.
pub fn render_markdown(issues : Array[Issue]) -> String {
  if issues.length() == 0 {
    return "| no findings |"
  }
  let out = StringBuilder()
  out.write_string("| severity | line | message |\n| --- | ---: | --- |\n")
  for it in issues {
    out.write_string(
      "| " +
      severity_name(it.severity) +
      " | " +
      it.line.to_string() +
      " | " +
      it.message +
      " |\n",
    )
  }
  out.to_string()
}

///|
/// Renders the point table grouped by Modbus area, with the registers sorted by
/// address within each area. Useful for eyeballing allocation before linting.
pub fn render_by_area(dev : Device) -> String {
  if dev.registers.length() == 0 {
    return "(empty point table)"
  }
  let out = StringBuilder()
  for area = 0; area <= 4; area = area + 1 {
    if area == 2 {
      continue // area 2 does not exist
    }
    out.write_string("## " + area_name(area) + "\n")
    out.write_string("| name | address | type | access | unit | jsonb |\n")
    out.write_string("| --- | ---: | --- | --- | --- | --- |\n")
    for r in dev.registers {
      if area_of(r.address) == area {
        out.write_string(
          "| " +
          r.name +
          " | " +
          r.address.to_string() +
          " | " +
          type_name(r.rtype) +
          " | " +
          access_name(r.access) +
          " | " +
          r.unit +
          " | " +
          r.jsonb +
          " |\n",
        )
      }
    }
  }
  out.to_string()
}

///|
/// A compact summary: total registers, how many errors/warnings, the areas
/// touched, and the number of registers with a jsonb mapping.
pub fn render_summary(dev : Device, issues : Array[Issue]) -> String {
  let mut errs = 0
  let mut warns = 0
  for it in issues {
    match it.severity {
      Error => errs = errs + 1
      Warning => warns = warns + 1
    }
  }
  let areas : Array[Int] = []
  let mut mapped = 0
  for r in dev.registers {
    let ar = area_of(r.address)
    if ar >= 0 && !areas.contains(ar) {
      areas.push(ar)
    }
    if !jsonb_is_unset(r.jsonb) {
      mapped = mapped + 1
    }
  }
  let mut area_names = ""
  for ar in areas {
    if area_names.length() > 0 {
      area_names = area_names + ", "
    }
    area_names = area_names + area_name(ar)
  }
  let out = StringBuilder()
  out.write_string("registers: " + dev.registers.length().to_string() + "\n")
  out.write_string(
    "areas: " + (if area_names == "" { "-" } else { area_names }) + "\n",
  )
  out.write_string("errors: " + errs.to_string() + "\n")
  out.write_string("warnings: " + warns.to_string() + "\n")
  out.write_string("jsonb-mapped: " + mapped.to_string() + "\n")
  out.to_string()
}

///|
test "render_markdown emits a table when there are findings" {
  let issues = [mk_issue(Error, 5, "dup name")]
  let md = render_markdown(issues)
  assert_eq(md.has_prefix("| severity | line | message |"), true)
  assert_eq(md.contains("| error | 5 | dup name |"), true)
}

///|
test "render_markdown handles an empty findings list" {
  assert_eq(render_markdown([]).has_prefix("| no findings |"), true)
}

///|
test "render_by_area lists holding registers" {
  let dev : Device = {
    registers: [
      {
        name: "a",
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "u",
        jsonb: "jsonb->a",
        line: 1,
      },
      {
        name: "b",
        address: 1001,
        rtype: TBit,
        access: Read,
        unit: "",
        jsonb: "jsonb->b",
        line: 2,
      },
    ],
  }
  let s = render_by_area(dev)
  assert_eq(s.contains("## holding registers"), true)
  assert_eq(s.contains("## coils"), true)
  assert_eq(s.contains("a | 40001 | int16 | R | u | jsonb->a"), true)
}

///|
test "render_summary counts errors, warnings and areas" {
  let dev : Device = {
    registers: [
      {
        name: "a",
        address: 40001,
        rtype: TInt16,
        access: Read,
        unit: "",
        jsonb: "jsonb->a",
        line: 1,
      },
      {
        name: "b",
        address: 1001,
        rtype: TBit,
        access: Read,
        unit: "",
        jsonb: "",
        line: 2,
      },
    ],
  }
  let issues = [mk_issue(Error, 1, "e"), mk_issue(Warning, 2, "w")]
  let s = render_summary(dev, issues)
  assert_eq(s.contains("registers: 2"), true)
  assert_eq(s.contains("errors: 1"), true)
  assert_eq(s.contains("warnings: 1"), true)
  assert_eq(s.contains("jsonb-mapped: 1"), true)
}
