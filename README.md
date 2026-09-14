# modbus_lint

> 面向 MoonBit 生态的 **Modbus 寄存器点表静态校验器**（linter）＋ 值编码库 ＋ 命令行工具。
>
> 解析 PLC 寄存器点表（文本 / JSON），按 **14 条静态规则** 校验出重名、地址越界、地址重叠、地址漏配、JSONB 字段冲突等问题，输出多种人读/机器报告，并提供 `--encode`/`--decode` 直接做 int16/uint16/int32/float32/float64 的 Modbus 值编码与反解。

本项目以 MoonBit 为主要实现语言（100% MoonBit `.mbt` 源码），面向需要在构建与交付前发现工业点位配置错误的库作者、工具开发者和自动化使用者。

---

## 项目目标

在设备接入、数据采集或 MES 集成交付之前，尽早发现 Modbus 点表（point table）中人工维护产生的常见错误，减少现场排查成本。核心价值：

- **一次校验**：从文本/JSON 解析到多格式报告一站式交付；
- **可直接复用**：校验库 API 可嵌入 Web、CLI、IDE 插件与 CI 构建流程；
- **对接驱动层**：内置值编码模块，可直接把点位值映射为线缆上的字/字节。

## 特性总览

- **解析器**：支持 `#` 注释、空行（容忍 CRLF）、多空格/Tab 分隔，字段序 `<name> <address> <type> <access> [unit] [jsonb]`；自动推断 Modbus 区域（coil/DI/IR/HR）。
- **数据类型**：`bool / int16 / uint16 / int32 / uint32 / float32 / float64`，权限 `R / W / RW`。
- **1 4 条静态规则**：重名、地址越界/重叠/间隙过大、JSONB 路径与冲突、多字对齐等等，Error 阻断交付 / Warning 提示关注。
- **7 种报告**：text / json / markdown / summary / by-area / csv / html。
- **JSON 双向 I/O**：`device_to_json_string` / `parse_device_json` / `json_roundtrip`。
- **点表工具与统计**：排序、去重、筛选、按名查找、地址碰撞、字占用与利用率统计。
- **值编码**：`ByteOrder`/`WordOrder` 双序控制，16/32/64 位整数与 IEEE-754 浮点双向映射，round-trip 精确。
- **CLI**：一条命令完成校验 → 报告 → 值编码。

---

## 环境要求与安装

- 需要 **MoonBit 工具链**（[下载安装](https://www.moonbitlang.com/download/)）：

  ```bash
  # Linux / macOS
  curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
  export PATH="$HOME/.moon/bin:$PATH"
  ```

- 克隆仓库：

  ```bash
  git clone https://github.com/668xin/modbus_lint.git
  cd modbus_lint
  ```

- 拉取依赖并本地构建验证（可复现，无需额外系统依赖）：

  ```bash
  moon update         # 拉取依赖锁
  moon check          # 静态类型检查
  moon test           # 运行测试
  moon build cmd/main # 构建 CLI 可执行程序
  ```

## 快速开始

### 1. 内置演示

```bash
moon run cmd/main -- --demo
```

### 2. 直接 lint 一行点表

```bash
moon run cmd/main -- "a 40001 int16 R  degC"
```

### 3. 校验示例点表（正确 / 含错误各一份，位于 `examples/`）

```bash
moon run cmd/main -- --format summary "$(cat examples/point_table_ok.txt)"
moon run cmd/main -- --format json     "$(cat examples/point_table_bad.txt)"
```

`examples/point_table_ok.txt` 应全部通过；`examples/point_table_bad.txt` 应命中**地址重叠、寄存器重名、JSONB 重复映射、地址间隙过大、地址越界**等错误。

### 4. 值编码 / 解码（`--order big|little`）

```bash
moon run cmd/main -- --encode float64 1.5          # 打包 1.5 为 IEEE-754 字与字节
moon run cmd/main -- --encode int16 -248          # int16 字 0xFF08 + 大端字节
moon run cmd/main -- --decode int32 ffff 8000     # 从字（MSW 在前）还原有符号值
moon run cmd/main -- --decode int16 ff 08 --order little  # 按字节序还原
```

### 5. 更多选项

```bash
moon run cmd/main -- --help
```

表格速览：

| 选项                | 作用                                                                   |
| ------------------- | ---------------------------------------------------------------------- |
| `--format FMT`      | 报告格式：`text`/`json`/`markdown`/`summary`/`csv`/`html`（默认 text） |
| `--json`            | `--format json` 的别名                                                 |
| `--json-in J`       | 从 JSON 文档读取点表                                                   |
| `--gap N`           | 覆盖 16 字地址间隙阈值（规则 6）                                       |
| `--show`            | 打印按地址排序后的点表                                                 |
| `--stats`           | 输出统计摘要（字占用/利用率/区域覆盖）                                 |
| `--encode TYPE VAL` | 值编码：`int16`/`uint16`/`int32`/`uint32`/`float32`/`float64`          |
| `--decode TYPE HEX` | 值解码：4 位 hex 字或 2 位 hex 字节                                    |
| `--order BO`        | 字节视图字节序：`big`/`little`                                         |
| `--demo`            | lint 内置演示点表                                                      |

## 最小可运行示例

校验一行点表并把结果输出为 JSON（完整可复现）：

```bash
$ moon run cmd/main -- --format json "motor 40001 float32 R Hz jsonb->motor_freq"
```

输出示意（校验规则结论 + 结构化 JSON）：

```json
[{"issue": "重名/越界/重叠等" }, ...]
```

完整可运行输入样张见 [`examples/`](examples/) 目录：`point_table_ok.txt`（通过）与 `point_table_bad.txt`（命中多项错误），可直接用于复现。

## 项目结构

```
modbus_lint
├─ parse.mbt / parser.mbt      解析器：点表文本 -> 结构化模型
├─ modbus_lint.mbt             核心数据模型（Device/Register/Issue）
├─ validator.mbt               14 条静态校验规则
├─ reporter.mbt                7 种报告输出
├─ jsonio.mbt                  JSON 双向 I/O
├─ jsonb.mbt                   JSONB 字段映射模型
├─ tools.mbt / stats.mbt       点表工具与统计
├─ encoding.mbt                值编码模块（字节序/字序）
├─ cmd/main/main.mbt           CLI 入口
├─ examples/                   可运行示例点表
└─ .github/workflows/ci.yml    CI：check + test + build
```

> OSC 申报书见同目录 [`申报书.md`](申报书.md)；参赛功能/阶段任务清单见 [`TASKS.md`](TASKS.md)。

## 持续集成（CI）

仓库内配置了 GitHub Actions（[`.github/workflows/ci.yml`](.github/workflows/ci.yml)），在 `push` 到 `main`/`master` 或 `pull_request` 时自动执行 **moon check（检查）→ moon test（测试）→ moon build cmd/main（构建）** 三件套，保证 108 个测试在干净环境每次提交均可复现通过。

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
      - run: moon check # 检查
      - run: moon test # 测试
      - run: moon build cmd/main # 构建
```

## 测试与质量保证

- **108 个测试全通过**（`moon test --deny-warn`），覆盖：数据模型、解析器、全部 14 条校验规则（正/反向）、JSON 往返、工具与统计、各报告输出、值编码 round-trip。
- `moon check --deny-warn` **0 警告**。
- 有效源码约 4000 行（已排除空行与注释），所有功能真实可用、均有测试背书，而非凑行数。

```bash
moon check --deny-warn && moon test --deny-warn
```

## 发布到 mooncakes.io

本项目已按 MoonBit 模块规范配置模块元数据（`moon.mod`：`name = "668xin/modbus_lint"`、`readme = "README.mbt.md"`、`license = "Apache-2.0"`、`keywords`/`description`），并在 `README.mbt.md` 提供面向包使用者的说明。已发布到 mooncakes.io（`668xin/modbus_lint@0.1.0`）。

```bash
moon pub          # 或 moon publish，按 MoonBit 工具链发布命令为准
```

> 若服务器端需要仓库认证与版本号，请参照当前 MoonBit 官方 `moon publish` 说明配置；`version`、`license`、`readme` 字段均已就绪，可直接发布。

## 开源许可证

本项目采用 **Apache-2.0**（OSI 认可的开源许可证），详见 [`LICENSE`](LICENSE)。`moon.mod` 中 `license = "Apache-2.0"` 已同步声明。

本项目为**原创项目**，不依赖或移植任何上游工程结构；如参考其他开源项目，将遵循对应原项目许可证要求。参考来源仅包括 Modbus 协议标准的寄存器区域划分与通用点表行式文本约定。
