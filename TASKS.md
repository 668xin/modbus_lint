# modbus_lint 功能完善 · 阶段任务文档

> 目标：把项目从约 1000 行源码扩充到接近章程 4~10k 行的规模参考，同时**全部功能真实有效、测试通过、编译零警告（`moon check --deny-warn` / `moon test`）**。
>
> 当前基线：26 个测试全通过，`moon check` 0 警告；已引入 `moonbitlang/core/json` 依赖（root `moon.pkg` 已加 import）。

## 已知坑点（先记下来，避免每个阶段重复踩）

- **T01 记录类型歧义（4034）**：给 JSON 新加的 `RegWire`/`DevWire` 与 `Register`/`Device` 字段同名，导致所有无注解的寄存器字面量（主要在 `validator.mbt` 测试里）报"Multiple possible record types detected"。→ 方案：wire 结构体改用**不同字段名**（如 `rtype_key`/`access_key`），或在构造处显式注解 `: Register`。
- **T02 priv wire 结构体 `derive(ToJson, FromJson)` 触发 "Unused trait implementation" 警告**（nightly 0001），会让 `--deny-warn` 失败。→ 方案：wire 结构体改 `pub`，或改为 **`Map[String, Json]` 中间表示**（`@json.to_json(Map)`/`from_json[Map]`），完全绕开自定义 derive。
- **T03 本工具链无裸 `try→Result`**：`try {}` 必须配 `catch {}`，用 `let x = try { ... } catch { ... }` 绑定非抛错值。
- **T04 给自定义枚举 `derive(Eq, Debug)` 会触发 `implicit_impl_as_method` 弃用警告**。→ 测试中枚举比较改用 `type_name()`/`access_name()` 字符串断言，不直接对枚举 `assert_eq`。

---

## 阶段 0 · 稳定编译（必须最先做）

**目标**：消除自 JSON 模块引入以来的回归，恢复零错误、零警告。

- [x] 解决 RegWire/Register 记录歧义（T01，已改用 `Map[String, Json]` 中间表示绕开）。
- [x] 解决 wire derive 的 "Unused trait implementation" 警告（T02，已用 `Map` 表示，无需自定义 derive）。
- [x] `moon check --deny-warn` 通过。
- [x] 现有测试 + 新增 JSON 测试全部通过（54/54）。

## 阶段 1 · JSON 导入导出模块（jsonio.mbt）

**目标**：Device/Issue 与 JSON 双向转换，schema 与文本关键字一致（`bool`/`R`/`error`）。

- [ ] `device_to_json_string(dev)` / `parse_device_json(text)` / `json_roundtrip(dev)` / `render_issues_json(issues)`。
- [ ] 关键字校验（非法 type/access 报错）与错误提示。
- [ ] 单元测试：round-trip、关键字存在性、畸形输入拒绝、非法关键字拒绝。

## 阶段 2 · 扩充校验规则（validator.mbt，7 → 12–15 条）

**目标**：新增真实有效的规则，全部有测试。

- R8 名称仅允许字母/数字/下划线/点/连字符（空名报错）。
- R9 地址必须 > 0（0 或负数报错）。
- R10 JSONB 路径解析（`jsonb->a.b.c`）合法性（点分路径）。
- R11 访问权限与可用性组合检查（如 `W` 型离散/读写寄存器的合理提醒）。
- R12 多字类型对齐检查（float32/float64 起始地址是否错位等）。
- R13 保留/首地址合理性（40001 起始等）可选项。
- 每新增一条规则配 ≥1 个正向 + 1 个负向测试。

## 阶段 3 · 报告格式扩充（reporter.mbt）

**目标**：多种机器/人读报告。

- [ ] `render_markdown(issues)`：Markdown 表格。
- [ ] `render_by_area(dev, issues)`：按区域（coil/DI/IR/HR）分组。
- [ ] `render_summary(dev, issues)`：各类错误/警告计数 + 区域覆盖统计。

## 阶段 4 · 点表工具与统计（tools.mbt / stats.mbt）

**目标**：可复用的分析能力。

- [ ] 工具：`sort_by_address`、`dedupe`、`filter_area`、`find_duplicate_addresses`、`lookup(name)`。
- [ ] 统计：按区域计数、按类型计数、按访问权限计数、地址密度、缺口列表。

## 阶段 5 · CLI 扩充（cmd/main）

**目标**：接入上面的能力。

- [ ] `--json-in <json>` 从 JSON 导入校验。
- [ ] `--format text|json|markdown|summary`。
- [ ] `--gap <n>` 覆盖规则 6 阈值。
- [ ] `--show` 展示排序后的点表。更新 `--help`。

## 阶段 6 · 文档与申报书更新

- [ ] README / README.mbt.md 补充 JSON、报告格式、新规则、工具示例。
- [ ] README（申报书）同步新增功能清单，保持"承诺=已实现"。

## 阶段 7 · 收尾验证与提交

- [ ] `moon check --deny-warn` / `moon test --deny-warn` / `moon fmt && git diff --exit-code` / `moon info`。
- [ ] 统计 `.mbt` 有效行数，评估是否接近 4k；不足则补充测试与边界用例。
- [ ] 一次性 commit，双端推送（github + gitlink）。

---

## 验收判据（每个阶段完成的标准）

- 新增代码**真实可用、有用**，绝非凑行数。
- `moon check` 与 `moon test` 通过；尽量保持 `--deny-warn` 零警告。
- 行数按阶段累计，最终逼近章程规模参考。
