// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "668xin/modbus_lint"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/668xin/modbus_lint"

license = "Apache-2.0"

keywords = [ "modbus", "linter", "mes", "plc", "cli", "validation" ]

preferred_target = "wasm-gc"

description = "General-purpose Modbus point-table linter: catches duplicate register names, out-of-range and overlapping addresses, oversized address gaps and conflicting JSONB field mappings."
