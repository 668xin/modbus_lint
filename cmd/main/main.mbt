// CLI entry point for modbus_lint.
//
// Usage:
//   moon run cmd/main -- --demo                        lint the built-in demo table
//   moon run cmd/main -- --format summary --demo       demo report in summary form
//   moon run cmd/main -- "a 40001 int16 R"             lint register lines given as args
//   moon run cmd/main -- --json-in "$(cat table.json)" lint a JSON point table
//   moon run cmd/main -- --gap 32 --show "a 40001..."  raise gap threshold + show sorted table
//   moon run cmd/main -- --help                        show usage
//
// Options:
//   --json        alias for --format json
//   --format FMT  report format: text | json | markdown | summary (default text)
//   --gap N       override the Rule-6 max address gap threshold (words)
//   --json-in J   read the point table from a JSON document instead of text lines
//   --show        print the point table sorted by address before the report
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
}

///|
fn main {
  let args = @env.args()
  let mut fmt = Text
  let mut gap_opt : Int? = None
  let mut json_in = ""
  let mut show = false
  let mut use_demo = false
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
    } else if a == "--help" {
      print_usage()
      return
    } else {
      lines.push(a)
    }
    i = i + 1
  }

  if use_demo {
    run_device(@modbus_lint.parse_device(example_text()), fmt, gap_opt, show)
    return
  }
  if json_in != "" {
    run_device(@modbus_lint.parse_device_json(json_in), fmt, gap_opt, show)
    return
  }
  if lines.length() == 0 {
    println("no input given; running the built-in demo point table:")
    println("")
    run_device(@modbus_lint.parse_device(example_text()), fmt, gap_opt, show)
    return
  }
  run_device(@modbus_lint.parse_device(join_lines(lines)), fmt, gap_opt, show)
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
    "  --format FMT   报告格式: text | json | markdown | summary（默认 text）",
  )
  println("  --json         --format json 的别名")
  println(
    "  --gap N        覆盖 Rule 6 最大地址间隙阈值（字，默认 16）",
  )
  println("  --json-in J    从 JSON 文档读取点表（而非文本行）")
  println("  --show         在报告前打印按地址排序后的点表")
  println("  --demo         校验内置演示点表")
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
) -> Unit {
  let dev = match parsed {
    Err(e) => {
      println("parse error: " + e)
      return
    }
    Ok(d) => d
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
