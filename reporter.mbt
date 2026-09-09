// Reporter: render lint findings into a human-readable, copy-pasteable report.

/// Render all findings. Returns a short "OK" message when there are none.
pub fn render(issues : Array[Issue]) -> String {
  if issues.length() == 0 {
    return "OK: no issues found."
  }
  var buf = ""
  var errs = 0
  var warns = 0
  for it in issues {
    match it.severity {
      Error => {
        errs = errs + 1
        buf =
          buf
          + "[ERROR] line "
          + it.line.to_string()
          + ": "
          + it.message
          + "\n"
      }
      Warning => {
        warns = warns + 1
        buf =
          buf
          + "[WARN]  line "
          + it.line.to_string()
          + ": "
          + it.message
          + "\n"
      }
    }
  }
  buf
  + "\nsummary: "
  + errs.to_string()
  + " error(s), "
  + warns.to_string()
  + " warning(s)."
}

/// Count findings with Error severity (used to decide a non-zero exit code).
pub fn error_count(issues : Array[Issue]) -> Int {
  var n = 0
  for it in issues {
    match it.severity {
      Error => n = n + 1
      Warning => n = n
    }
  }
  n
}

/// 转义 JSON 字符串中的引号与反斜杠。
fn escape(s : String) -> String {
  var out = ""
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c == '"' {
      out = out + "\\\""
    } else if c == '\\' {
      out = out + "\\\\"
    } else {
      out = out + c.to_string()
    }
  }
  out
}

/// 以 JSON 数组形式输出，便于 CI 或其他工具消费。
pub fn render_json(issues : Array[Issue]) -> String {
  var buf = "[\n"
  for i = 0; i < issues.length(); i = i + 1 {
    let it = issues[i]
    let sev = match it.severity {
      Error => "error"
      Warning => "warning"
    }
    buf =
      buf
      + "  {\"severity\": \""
      + sev
      + "\", \"line\": "
      + it.line.to_string()
      + ", \"message\": \""
      + escape(it.message)
      + "\"}"
    if i + 1 < issues.length() {
      buf = buf + ","
    }
    buf = buf + "\n"
  }
  buf + "]"
}

test "render reports OK when clean" {
  assert_eq(render([]), "OK: no issues found.")
}

test "render counts errors and warnings" {
  let issues = [
    mk_issue(Error, 1, "dup name"),
    mk_issue(Warning, 2, "weird jsonb"),
  ]
  assert_eq(error_count(issues), 1)
  assert_eq(render(issues).length() > 0, true)
  assert_eq(error_count([mk_issue(Warning, 3, "only a warning")]), 0)
}

test "render_json emits one object per finding" {
  let issues = [mk_issue(Error, 7, "dup name")]
  assert_eq(
    render_json(issues),
    "[\n  {\"severity\": \"error\", \"line\": 7, \"message\": \"dup name\"}\n]",
  )
}

test "render_json on empty findings is an empty array" {
  assert_eq(render_json([]), "[\n]")
}
