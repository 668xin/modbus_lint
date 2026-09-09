// CLI entry point for modbus_lint.
//
// Usage:
//   moon run cmd/main                      run the built-in demo point table
//   moon run cmd/main -- "a 40001 int16 R" lint register lines given as args
//   moon run cmd/main -- "$(cat table.txt)"  lint a whole file (shell quoted)
//
// The CLI deliberately depends only on moonbitlang/core (`env` + `println`),
// so it runs anywhere MoonBit runs without extra dependencies.

fn main {
  let args = @env.args()
  if args.length() == 0 {
    println("no input given; running the built-in demo point table:")
    println("")
    run_text(example_text())
    return
  }
  run_text(join_lines(args))
}

/// Join argument lines back into a point-table document.
fn join_lines(lines : Array[String]) -> String {
  var out = ""
  for i = 0; i < lines.length(); i = i + 1 {
    if i > 0 {
      out = out + "\n"
    }
    out = out + lines[i]
  }
  out
}

/// Parse, lint and print a point-table document.
fn run_text(text : String) -> Unit {
  match parse_device(text) {
    Err(e) => {
      println("parse error: " + e)
      return
    }
    Ok(dev) => {
      let issues = lint(dev)
      println(render(issues))
    }
  }
}

/// A small demo table that intentionally contains one address overlap so the
/// linter output is easy to see.
fn example_text() -> String {
  "# washer line 1 - demo (contains one intentional overlap)\n"
  + "coil_temp   40001 float32 R  degC  jsonb->coil_temp\n"
  + "conveyor    40003 bool    RW        jsonb->conveyor_run\n"
  + "tank_level  40004 uint16  R   mm    jsonb->tank_level\n"
  + "spray_prs   40005 uint16  R   kPa   jsonb->spray_press\n"
  + "big_val     40010 float32 R         jsonb->big_val\n"
  + "small_val   40011 int16   R         jsonb->small_val\n"
}
