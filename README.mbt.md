# modbus_lint

A Modbus point-table linter written in MoonBit.

It parses a plain-text register point table and reports common mistakes:
duplicate register names, out-of-range addresses, registers spilling past the
end of their Modbus area, address overlaps inside one area, malformed JSONB
field names, and more (see the rules below). Devices and lint findings can also
move in and out of JSON, making it a drop-in checker for toolchains that already
model points as JSON.

## Point table format

One register per line; `#` starts a comment. The Modbus area is inferred from
the address prefix (coils 1-9999, discrete inputs 10001-19999, input registers
30001-39999, holding registers 40001-49999).

```
# name  address type     access unit  jsonb
coil_temp 40001 float32 R degC jsonb->coil_temp
conveyor  40003 bool    RW      jsonb->conveyor_run
tank_level 40004 uint16 R mm    jsonb->tank_level
```

Supported types: `bool` `int16` `uint16` `int32` `uint32` `float32` `float64`.
Access: `R` `W` `RW`.

## Rules

The `lint(device)` entry point (and `lint_with_gap(device, threshold)` for a
custom address-gap threshold) reports `Error`/`Warning` findings:

1. Duplicate register names.
2. Address outside a standard Modbus area.
3. A multi-word register spilling past the end of its area.
4. Address overlap inside one area (word-aware).
5. Malformed `jsonb->` dotted path.
6. Large address gap (threshold 16 words) suggesting a missing or mistyped entry.
7. Multiple registers mapping to the same JSONB field.
8. Name not in `[A-Za-z0-9_.-]` (empty name is an error).
9. Multi-word type used in a bit-addressed area (coil / DI).
10. Write access declared on an input-only area (DI / IR).
11. Names differing only by letter case.

## Usage

```moonbit nocheck
let dev = @modbus_lint.parse_device(text)?
let issues = @modbus_lint.lint(dev)
println(@modbus_lint.render(issues))
```

JSON round-trip, multiple report formats and point-table tools are all exposed:

```moonbit nocheck
let s = @modbus_lint.device_to_json_string(dev)   // Device -> pretty JSON
let back = @modbus_lint.parse_device_json(s)?      // JSON -> Device
println(@modbus_lint.render_summary(dev, issues))  // errors/warnings + coverage
let sorted = @modbus_lint.sort_by_address(dev)     // tools.sort_by_address
```

Or run the CLI:

```bash
moon run cmd/main                        # built-in demo
moon run cmd/main -- "a 40001 int16 R"   # lint given register line
moon run cmd/main -- --format summary --demo
moon run cmd/main -- --json-in "$(cat points.json)"
moon run cmd/main -- --gap 32 --show "coil_temp 40001 int16 R degC"
```

Use `--help` for the full option list; `--format` accepts
`text|json|markdown|summary`, `--gap N` overrides the gap threshold, and
`--show` prints the point table sorted by address first.

## Layout

- `modbus_lint.mbt` — data model and pure helpers (`pad`, `area_of`, ...)
- `parser.mbt` — text to `Device`
- `validator.mbt` — lint rules
- `reporter.mbt` — text / JSON / Markdown / by-area / summary reports
- `jsonio.mbt` — Device & Issue <-> JSON conversion
- `jsonb.mbt` — `jsonb->` dotted-path parsing and validation
- `tools.mbt` — sorting, dedupe, filtering, lookup, stats
- `cmd/main/main.mbt` — CLI entry point