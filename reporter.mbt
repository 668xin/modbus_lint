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
