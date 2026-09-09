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

name = "dengxinxin/modbus_lint"

version = "0.1.0"

readme = "README.mbt.md"

// TODO: 报名/发布前替换为你的公开仓库地址（赛事要求仓库公开可访问）
repository = ""

license = "Apache-2.0"

keywords = ["modbus", "linter", "mes", "plc", "cli", "validation"]

preferred_target = "wasm-gc"

description = "Modbus point-table linter for MES device onboarding: catches duplicate register names, out-of-range and overlapping addresses, oversized address gaps and conflicting JSONB mappings."
