// CLI entry point for modbus_lint.
//
// Usage:
//   moon run cmd/main                        run the built-in demo point table
//   moon run cmd/main -- --demo              same as above
//   moon run cmd/main -- --json --demo       demo report in JSON
//   moon run cmd/main -- "a 40001 int16 R"   lint register lines given as args
//   moon run cmd/main -- "$(cat table.txt)"  lint a whole file (shell quoted)
//   moon run cmd/main -- --help              show usage
//
// The CLI depends only on moonbitlang/core (`env` + `println`), so it runs
// anywhere MoonBit runs, without extra dependencies.

///|
fn main {
  let args = @env.args()
  let mut json_mode = false
  let mut use_demo = false
  let lines : Array[String] = []
  for i = 0; i < args.length(); i = i + 1 {
    let a = args[i]
    if a == "--json" {
      json_mode = true
    } else if a == "--demo" {
      use_demo = true
    } else if a == "--help" {
      print_usage()
      return
    } else {
      lines.push(a)
    }
  }
  if use_demo {
    run_text(example_text(), json_mode)
    return
  }
  if lines.length() == 0 {
    println("no input given; running the built-in demo point table:")
    println("")
    run_text(example_text(), json_mode)
    return
  }
  run_text(join_lines(lines), json_mode)
}

///|
/// Print the CLI help text.
fn print_usage() -> Unit {
  println("modbus_lint - Modbus point table linter")
  println("")
  println("usage: moon run cmd/main -- [options] [register lines...]")
  println("")
  println("options:")
  println("  --json   输出 JSON 格式报告")
  println("  --demo   校验内置演示点表")
  println("  --help   显示本帮助")
}

///|
/// Join argument lines back into a point-table document.
fn join_lines(lines : Array[String]) -> String {
  let mut out = ""
  for i = 0; i < lines.length(); i = i + 1 {
    if i > 0 {
      out = out + "\n"
    }
    out = out + lines[i]
  }
  out
}

///|
/// Parse, lint and print a point-table document.
fn run_text(text : String, json_mode : Bool) -> Unit {
  match @modbus_lint.parse_device(text) {
    Err(e) => {
      println("parse error: " + e)
      return
    }
    Ok(dev) => {
      let issues = @modbus_lint.lint(dev)
      if json_mode {
        println(@modbus_lint.render_json(issues))
      } else {
        println(@modbus_lint.render(issues))
      }
    }
  }
}

///|
/// A small demo table that intentionally contains one address overlap so the
/// linter output is easy to see.
fn example_text() -> String {
  "# example point table - demo (contains one intentional overlap)\n" +
  "coil_temp   40001 float32 R  degC  jsonb->coil_temp\n" +
  "conveyor    40003 bool    RW        jsonb->conveyor_run\n" +
  "tank_level  40004 uint16  R   mm    jsonb->tank_level\n" +
  "spray_prs   40005 uint16  R   kPa   jsonb->spray_press\n" +
  "big_val     40010 float32 R         jsonb->big_val\n" +
  "small_val   40011 int16   R         jsonb->small_val\n"
}
