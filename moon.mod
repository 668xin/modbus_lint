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

name = "aoliaoxiaoxin/modbus_lint"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://gitee.com/aoliaoxiaoxin/modbus_lint"

license = "Apache-2.0"

keywords = ["modbus", "linter", "mes", "plc", "cli", "validation"]

preferred_target = "wasm-gc"

description = "Modbus point-table linter for MES device onboarding: catches duplicate register names, out-of-range and overlapping addresses, oversized address gaps and conflicting JSONB mappings."
