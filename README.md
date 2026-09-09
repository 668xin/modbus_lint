# modbus_lint — Modbus 点表校验器（MoonBit）

> 2026 MoonBit 九月黑客松 · 用 MoonBit + AI 编程工具，把一个真实需求做成可运行、可测试、可维护的软件。

`modbus_lint` 是一个用 **MoonBit** 编写的 Modbus 寄存器点表（point table）静态校验工具：它读取一份点表文本，检查**寄存器重名、地址越界、跨区溢出、同区地址重叠、JSONB 字段命名**等常见错误，并输出带行号、可读、可贴回工单的报告。既能作为 `mooncakes.io` 上的**库**复用，也带一个可直接演示的 **CLI**。

---

## 一、项目一页纸（报名用）

- **项目概述**：面向工业设备接入与数据采集场景，对 **Modbus 寄存器点表**做通用静态校验——不绑定任何具体设备、厂商或上位机系统。核心是一个与设备无关的纯函数校验引擎：输入点表，输出可定位到行号的问题清单，并附带一个可直接运行的命令行工具。
- **工程目标**：把"人工核点表"这种易漏、慢、不可复现的工作，变成"一行命令、可进 CI"的确定性检查；输出清晰、模块化、带测试、可维护的 MoonBit 工程。
- **技术路线**：`model`（数据模型/辅助）→ `parser`（文本→Device）→ `validator`（规则）→ `reporter`（报告）→ `cli`（入口）。全程无副作用，核心库**不依赖文件 IO**，便于单测；Modbus 区域由地址前缀自动判定。
- **可行性**：范围自包含（解析 + 校验），不触碰数据库/网络；MoonBit 的代数数据类型与模式匹配非常契合点表建模与报错；MVP 体量可控（数百行），并可按阶段演进到数千行。
- **真实需求**：点表地址重叠、寄存器重名、类型与字宽不匹配，是 Modbus 设备接入与现场调试时最常见的踩坑点；本项目正是为这个通用痛点而生。

## 二、点表格式

一行一个寄存器，`#` 开头为注释；Modbus 区域由地址前缀自动判定（线圈 1-9999、离散输入 10001-19999、输入寄存器 30001-39999、保持寄存器 40001-49999）。

```
# 示例点表（保持寄存器）
# 名称        地址    类型     读写  单位   JSONB 字段
coil_temp   40001   float32  R    degC  jsonb->coil_temp
conveyor    40003   bool     RW         jsonb->conveyor_run
tank_level  40004   uint16   R    mm    jsonb->tank_level
spray_prs   40005   uint16   R    kPa   jsonb->spray_press
```

支持的类型：`bool` `int16` `uint16` `int32` `uint32` `float32` `float64`；读写：`R` `W` `RW`。

## 三、校验规则

| # | 规则 | 严重级别 |
|---|------|----------|
| 1 | 寄存器名重复 | Error |
| 2 | 地址越出任何标准 Modbus 区域 | Error |
| 3 | 多字寄存器跨出所在区域末尾（如 float32 放在 49999） | Error |
| 4 | 同区域内两个寄存器地址重叠（按类型字宽计算） | Error |
| 5 | JSONB 字段不是合法标识符 | Warning |
| 6 | 地址间隙过大（> 16 字），可能漏配或地址笔误 | Warning |
| 7 | 多个寄存器映射到同一个 JSONB 字段（采集时互相覆盖） | Warning |

## 四、使用方法

前置：安装 MoonBit 工具链（<https://www.moonbitlang.cn/download>）。

```bash
# 1. 类型检查（不生成产物）
moon check

# 2. 运行单元测试
moon test

# 3. 运行内置演示点表
moon run cmd/main -- --demo

# 4. 校验自己的点表（用 shell 把文件内容作为一个参数传入）
moon run cmd/main -- "$(cat my_point_table.txt)"

# 4a. 用仓库自带示例验证（可复现演示）
moon run cmd/main -- "$(cat examples/point_table_ok.txt)"    # 正确示例：应无问题
moon run cmd/main -- "$(cat examples/point_table_bad.txt)"   # 错误示例：命中多条规则

# 5. 输出 JSON 报告（便于接入 CI / 被其他工具消费）
moon run cmd/main -- --json "$(cat my_point_table.txt)"

# 6. 快速校验几行
moon run cmd/main -- "coil_temp 40001 float32 R degC jsonb->coil_temp"

# 7. 查看用法
moon run cmd/main -- --help
```

> **为什么用 shell 传参而不是直接读文件？** MoonBit 核心库 `moonbitlang/core` 不含文件 IO，
> 本项目刻意保持**零外部依赖**，因此 CLI 通过 `@env.args()` 接收点表内容（一行一个参数，
> 或把整个文件作为一个带换行的参数传入）。若需要直接读文件路径，可执行 `moon add moonbitlang/x/fs`
> 后改用 `@fs.read_to_string`。

在代码中作为库使用：

```moonbit
let dev = @modbus_lint.parse_device(text)?
let issues = @modbus_lint.lint(dev)
println(@modbus_lint.render(issues))       // 人读
println(@modbus_lint.render_json(issues))  // 机器读
```

## 五、架构与模块边界

```
moon.mod / moon.pkg          模块与包配置
modbus_lint.mbt              数据模型 + 纯函数辅助（word_count / area_of / 解析小工具）
parser.mbt                   parse_device：文本 → Device（Result）
validator.mbt                lint：Device → Array[Issue]（规则 1-5）
reporter.mbt                 render / error_count：Issue → 可读报告
cmd/main/main.mbt            CLI 入口（读文件 / 内置演示 → 解析 → 校验 → 打印）
*_test / 内联 test 块         单元测试（黑盒 + 白盒）
.github/workflows/ci.yml     CI：moon check + moon test + build
```

设计要点：核心库（model/parser/validator/reporter）**全程纯函数、零 IO**，可独立单测；CLI 只做输入输出胶水。模块边界清晰，符合赛事对"清晰模块化与工程结构"的要求。

## 六、分阶段开发计划（对齐"分阶段完成 + 合格提交次数"要求）

赛事要求**公开持续提交、保留 Issues/PR 与更新记录**，且**合格提交次数需达标**。按下面的阶段推进，每个阶段产生若干次有主题的公开提交（建议配合 Issue + PR，过程可追踪）：

| 阶段 | 交付 | 建议提交 |
|------|------|----------|
| S0 申报 | 公开仓库 + 一页纸说明（本 README 骨架） | 1-2 次 |
| S1 模型与解析 | model + parser + 单测 | 3-4 次 |
| S2 校验规则 | validator 五条规则 + 单测 | 3-4 次 |
| S3 报告与 CLI | reporter + cli + 演示 | 2-3 次 |
| S4 工程化 | README 完善、CI、mooncakes 发布、文档 | 2-3 次 |
| S5 验收材料 | 可复现演示说明 + 开发复盘（AI 使用说明） | 1-2 次 |

合计约 **12-16 次公开提交**，分布在 9 月第一周—24 日之间，既能满足"持续提交"，也通常**高于合格提交次数门槛**。
（若你知道具体门槛数字，告诉我，我可把阶段拆得更细以刚好达标。）

## 七、验收对照（满足活动要求）

| 活动要求 | 本项目的落点 |
|----------|--------------|
| 以 MoonBit 为主要实现语言 | 全部核心代码为 `.mbt` |
| 使用 AI 编程工具 | 见"八、AI 使用说明"，并在复盘文档中说明 |
| 真实需求 → 可运行/可测试/可维护 | Modbus 点表校验；`moon test` + `moon run`；模块化纯函数设计 |
| 公开仓库 + 完整 commit 历史 | 分阶段公开提交（见六） |
| README + 可运行示例 + 可复现演示 | 本文件 + `moon run cmd/main` 内置演示 |
| CI + 测试 | `.github/workflows/ci.yml` + 内联/黑盒单测 |
| OSI 开源许可证 | Apache-2.0（见 LICENSE） |
| mooncakes.io 发布 | 发布为库（`moon publish`） |

## 八、AI 工具使用说明（评审"Explainability"维度）

本项目的架构拆分、校验规则设计与样板代码由 AI 辅助生成；规则语义（Modbus 字宽、地址分区、重叠判定）经人工核对与单测约束。提交时请在仓库补充一份开发复盘，说明：关键架构决策、AI 在各阶段的作用、以及参考了哪些现有开源实现。

---

## 许可

Apache-2.0，见 [LICENSE](./LICENSE)。
