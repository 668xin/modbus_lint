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

> **一句话：一套可独立运行的 Modbus 点位校验库 + 命令行工具，从「文本/JSON 解析」到「14 条静态规则校验」再到「多格式报告」，一站式交付；并内置 IEEE-754 浮点值编码，可直接对接驱动层。**

**① 解析与数据模型**

- **健壮的点表解析器**：支持 `#` 注释行、空行（容忍 CRLF）、多空格与 Tab 分隔，字段顺序 `<name> <address> <type> <access> [unit] [jsonb]`；
- 完整寄存器数据模型：名称、地址、数据类型、读写权限、工程单位与 JSONB 字段映射，并**自动从地址前缀推断 Modbus 区域**（coil / DI / IR / HR）；
- 类型与权限全覆盖：`bool / int16 / uint16 / int32 / uint32 / float32 / float64`，访问权限 `R / W / RW`。

**② 静态校验规则（14 条，Error 阻断交付 / Warning 提示关注）**

统一入口 `lint(device)`（及可配阈值版本 `lint_with_gap(device, threshold)`），一次输出全部发现：

- **结构性错误（Error）**——
  1. 寄存器名称必须唯一（重名检测）；
  2. 地址必须落在标准 Modbus 区域内（coils 1-9999、DI 10001-19999、IR 30001-39999、HR 40001-49999）；
  3. 多字寄存器不得越过所在区域末尾；
  4. 同一区域内寄存器按字宽计算后不得发生地址重叠；
  5. 名称仅允许字母/数字/下划线/点/连字符（空名报错）。
- **易错点预警（Warning）**—— 5. 非空 JSONB 字段应为合法标识符（`jsonb->` 点分路径）且**嵌套深度过深**（R12）；6. 相邻寄存器地址间隙过大（阈值 16 字，`--gap` 可覆盖）提示可能漏配或笔误；7. 多个寄存器映射到同一 JSONB 字段、采集时会互相覆盖；9. 位寻址区域（coil/DI）中不得使用多字类型；10. 输入型区域（DI/IR）中不允许声明写与读写权限；11. 名称仅大小写不同的寄存器易被误用；13. 使用保留/特殊关键字命名易与协议冲突；14. 32 位类型建议落在区域内**偶数字偏置**，避免寄存器错位。

**③ 多种报告格式（7 种）**

**按需输出人读或机器可消费报告**：人类可读文本 `render`、CI 可消费 JSON `render_json`、Markdown 表格 `render_markdown`、按区域分组 `render_by_area`、错误/警告计数与区域覆盖统计 `render_summary`、表格 CSV `render_csv`、网页 HTML `render_html`。

**④ JSON 双向 I/O**

设备与发现的双向 JSON 转换（`device_to_json_string` / `parse_device_json` / `json_roundtrip` / `render_issues_json`），**以 JSON 作为点表的机器输入/交付接口**。

**⑤ 点表工具与统计**

按地址排序 `sort_by_address`、精确去重 `dedupe`、按区域筛选 `filter_area`、按名查找 `lookup`、地址重叠碰撞 `exact_address_collisions`；以及按区域/类型/访问权限分类计数、区域字占用 `per_area_words`、字利用率与间隙区间等统计。

**⑥ 值编码模块（encoding.mbt）**

**面向驱动层的 IEEE-754 浮点编码**：`ByteOrder`/`WordOrder` 双序控制，`int16/uint16/int32/float32/float64` 与 16 位字的双向映射，并支持大/小端字节序下的字节级序列化（`float32_bytes`/`float64_bytes`），全部 round-trip 精确。

**⑦ 命令行工具（CLI）**

一条命令完成校验到交付：传入点表文本 / `--json-in` 读 JSON 点表 / `--demo` 演示、`--format text|json|markdown|summary|csv|html` 切换报告、`--gap N` 覆盖间隙阈值、`--show` 打印排序点表、`--stats` 统计摘要，以及 **`--encode`/`--decode` 直接进行 float32/float64 值编码与反解**（`--order big|little` 控字节序），便于接入构建与交付、甚至在线调试。

**质量保证**：单元测试 + 黑盒测试覆盖数据模型、解析器、全部校验规则、JSON 往返、工具统计、报告输出与值编码，持续保持核心回归测试通过。

## 移植或参考说明

- 本项目为原创实现，不依赖任何上游代码或工程结构。判断依据参考 Modbus 协议的点位组织方式与通用工程点表的 JSONB 采集映射约定；
- 参考来源：Modbus 协议寄存器区域划分（标准地址区间），以及工业点表常见的 `<name> <addr> <type> <access> [unit] [jsonb]` 行式文本约定；
- 本项目许可证：Apache-2.0；
- 说明：
  - 我看了mooncakes库中有关modbus的工具和我写的这个在本质上是完全不同的项目。
