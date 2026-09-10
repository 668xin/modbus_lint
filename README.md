# modbus_lint 项目申报书

## 基本信息

- 项目名称：modbus_lint：Modbus 点表静态校验器

- 仓库链接：`https://gitee.com/aoliaoxiaoxin/modbus_lint.git`
- 镜像仓库：
  - Gitlink：`https://gitlink.org.cn/aoliaoxiaoxin/modbus_lint.git`
  - GitHub：`git@github.com:668xin/modbus_lint.git`
- 项目方向：Modbus 数据点表校验 / PLC·MES 配置静态分析工具
- 是否为移植项目：否（原创项目）

## 项目简介

modbus_lint 是一个面向 MoonBit 生态的 Modbus 寄存器点表（point table）静态校验器。工业现场中，PLC 寄存器点表通常以文本形式人工维护，容易出现点重名、地址越界、同区地址重叠、地址漏配以及 JSONB 字段互相覆盖等错误；在设备接入、数据采集或 MES 集成交付前发现这些错误，能显著减少现场排查成本。

本项目以 MoonBit 原生类型系统和测试框架实现了一个可独立运行、可嵌入复用的校验库与 CLI：解析点表文本为结构化模型，按规则输出人类可读报告或 CI 可消费的 JSON 报告，并可用于 Web、CLI、IDE 插件和自动化构建流程中。面向需要在 MoonBit 中处理 Modbus 点位配置的库作者、工具开发者和自动化测试使用者。

## 核心功能范围

- 提供点表解析器，支持 `#` 注释行、空行（容忍 CRLF）、多空格与 Tab 分隔，字段顺序为 `<name> <address> <type> <access> [unit] [jsonb]`；
- 提供寄存器数据模型，覆盖名称、地址、数据类型、读写权限、工程单位与 JSONB 字段映射，并自动从地址前缀推断 Modbus 区域（coil / DI / IR / HR）；
- 支持 `bool / int16 / uint16 / int32 / uint32 / float32 / float64` 数据类型，以及 `R / W / RW` 访问权限；
- 提供统一校验入口 `lint(device)`（与可配阈值的 `lint_with_gap(device, threshold)`），按下列 11 条规则输出全部发现（Error/Warning）：
  1. 寄存器名称必须唯一（重名检测）；
  2. 地址必须落在标准 Modbus 区域内（coils 1-9999、DI 10001-19999、IR 30001-39999、HR 40001-49999）；
  3. 多字寄存器不得越过所在区域末尾；
  4. 同一区域内寄存器按字宽计算后不得发生地址重叠；
  5. 非空的 JSONB 字段应为合法标识符（`jsonb->` 点分路径，警告）；
  6. 同一区域内相邻寄存器地址间隙过大（阈值 16 字，可用 `--gap` 覆盖）时提示可能漏配或笔误（警告）；
  7. 多个寄存器映射到同一个 JSONB 字段、采集时会互相覆盖（警告）；
  8. 寄存器名称仅允许字母/数字/下划线/点/连字符（空名报错，异常字符警告）；
  9. 位寻址区域（coil/DI）中不得使用多字类型（警告）；
  10. 输入型区域（DI/IR）中不允许声明写与读写权限（警告）；
  11. 名称仅大小写不同的寄存器易被误用（警告）。
- 提供多种报告格式：人类可读文本 `render`、CI 可消费 JSON `render_json`、Markdown 表格 `render_markdown`、按区域分组 `render_by_area`，以及覆盖错误/警告计数与区域/JSONB 映射统计的 `render_summary`；
- 提供设备与发现的双向 JSON 转换（`device_to_json_string` / `parse_device_json` / `json_roundtrip` / `render_issues_json`），支持以 JSON 作为点表的机器输入接口；
- 提供点表工具与统计：按地址排序 `sort_by_address`、精确去重 `dedupe`、按区域筛选 `filter_area`、按名查找 `lookup`、地址重叠碰撞 `exact_address_collisions`，以及按区域/类型/访问权限分类计数、区域字占用 `per_area_words` 等；
- 提供 CLI 入口：支持传入点表文本、读取 JSON 点表 `--json-in`、校验内置示例点表 `--demo`、切换报告格式 `--format text|json|markdown|summary`、覆盖地址间隙阈值 `--gap N`、打印按地址排序点表 `--show`，以及 `--json` / `--help`，便于直接接入构建与交付流程；
- 提供单元测试与黑盒测试，覆盖数据模型、解析器、校验规则、JSON 往返、工具统计与报告输出，并持续保持核心回归测试通过；
- 提供 README 示例，覆盖点表文本解析、跨区域校验、JSON 报告与 CLI 使用。

## 移植或参考说明

- 本项目为原创实现，不依赖任何上游代码或工程结构。判断依据参考 Modbus 协议的点位组织方式与通用工程点表的 JSONB 采集映射约定；
- 参考来源：Modbus 协议寄存器区域划分（标准地址区间），以及工业点表常见的 `<name> <addr> <type> <access> [unit] [jsonb]` 行式文本约定；
- 本项目许可证：Apache-2.0；
- 设计取舍：
  - 使用 MoonBit 原生包结构、代数数据类型与测试机制组织代码，而非复刻任何桌面或插件工程结构；
  - 以文本与 JSON 作为主要输入/交付接口，便于接入 Web、CLI、IDE 与 CI 场景；
  - 数字解析、行切分、字宽计算等均不依赖第三方库，行为在不同后端（Wasm 等）上保持一致；
  - 校验规则采用"Error 阻断交付 / Warning 提示关注"的分级策略，便于在自动化流程中断言失败条件。
