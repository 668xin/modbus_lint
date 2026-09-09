# modbus_lint

A Modbus point-table linter written in MoonBit.

It parses a plain-text register point table and reports common mistakes:
duplicate register names, out-of-range addresses, registers spilling past the
end of their Modbus area, address overlaps inside one area, and malformed JSONB
field names.

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

## Usage

```moonbit nocheck
let dev = @modbus_lint.parse_device(text)?
let issues = @modbus_lint.lint(dev)
println(@modbus_lint.render(issues))
```

Or run the CLI:

```bash
moon run cmd/main                        # built-in demo
moon run cmd/main -- "a 40001 int16 R"   # lint given lines
```

## Layout

- `modbus_lint.mbt` — data model and pure helpers
- `parser.mbt` — text to `Device`
- `validator.mbt` — lint rules
- `reporter.mbt` — human readable report
- `cmd/main/main.mbt` — CLI entry point
