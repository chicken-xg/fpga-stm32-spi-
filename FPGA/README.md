# FPGA_xc7a35t — DAC904 波形发生器工程（v2.0）

## 工程概况

| 项目 | 内容 |
| ---- | ---- |
| 工程名称 | FPGA_xc7a35t |
| 器件型号 | xc7a35tfgg484-2 |
| 开发板 | 黑金 AX7A035B（板载 200MHz 差分系统时钟：SYS_CLK_P=R4 / SYS_CLK_N=T4） |
| 开发工具 | Vivado 2022.2 |
| 顶层模块 | DAC904_TOP |
| 比特流 | `output/DAC904_TOP.bit` |

## 功能简述

基于 DAC904 的 14 位波形发生器，由 STM32 通过 SPI 下发命令控制：

- 输出波形：正弦波 / 三角波 / 方波循环切换；
- 采样时钟：板载 200MHz 差分时钟内部 4 分频得 50MHz，经 MMCM（`pll_165m`）产生 165MHz 采样时钟；
- 波形数据：正弦、三角波通过 ROM 查表输出（4096 × 14 位，`.coe` 初始化），方波由相位累加器最高位生成；
- 控制接口：SPI 从机（Mode0、MSB-first、8 位）与 STM32 软件 SPI 通信，取代原 4 按键方案；
- **自动扫频（v2.0 新增）**：命令 `0x07` 从 1kHz 启动，每隔 1s 步进 1kHz，到达 100MHz 后回卷到 1kHz 循环；
- 辅助功能：1s 闸门频率计、LED 波形 / 频率计状态指示、比较器反馈测频；
- 顶层注释注明 DAC904 输出电压转换公式：`(16383 - DAC_DATA) × (6V / 16383)`。

## SPI 命令协议

SPI Mode0：空闲 SCK 低电平，上升沿采样，MSB 先行，每帧 8 位；NSS 低有效，帧结束由 NSS 上升沿识别；MISO 在片选有效时回显 MOSI，供 STM32 做 `g_rx == g_tx` 回环校验。

| 命令码 | 二进制 | 功能 |
| ---- | ---- | ---- |
| `0x01` | `0001` | 频率升高一档（按当前频段自适应步进） |
| `0x02` | `0010` | 波形循环切换：正弦 → 三角 → 方波 → 正弦 |
| `0x03` | `0011` | 频率降低一档 |
| `0x04` | `0100` | 频率计使能开关 |
| `0x05` | `0101` | 频率固定增加 1kHz |
| `0x06` | `0110` | 频率固定降低 1kHz |
| `0x07` | `0111` | 从 1kHz 启动 / 重启自动扫频 |
| `0x08` | `1000` | 软复位：1kHz、正弦波、频率计开启、相位清零 |

其他命令码忽略，保持当前状态不变。

### 自动扫频规则

- 每次收到 `0x07` 都从 1kHz 重新开始扫频；
- 每 `165 000 000` 个 165MHz 周期（1s）频率字增加一次，步长对应约 1kHz；
- 到达 100MHz 后回卷到 1kHz 继续；
- 手动频率命令 `0x01` / `0x03` / `0x05` / `0x06` 与软复位 `0x08` 停止扫频；
- 波形切换 `0x02`、频率计开关 `0x04` 不中断正在运行的扫频。

### 频率公式

```text
f_out = fre_k × 165MHz / 2^32
```

`fre_k = 26031` 对应约 1kHz，`2 603 100 000` 对应约 100MHz。

## 目录结构

```
FPGA/
├── rtl/          # RTL 源码（13 个 .v）
├── sim/          # 仿真测试平台（3 个 tb_*.v）
├── constrs/      # 管脚与时序约束 top.xdc
├── ip/           # IP 核定义（pll_165m / rom_sin / rom_tri 的 .xci）
├── rom/          # ROM 初始化数据（Sin_Wave.coe / Tri_Wave.coe）
├── scripts/      # 辅助脚本（recreate_project.tcl / encoding.ps1 / mif2coe.ps1）
├── docs/         # 开发文档（移植记录、SPI 合并记录、系统总结）
├── output/       # 综合实现产物（DAC904_TOP.bit）
└── FPGA_xc7a35t.xpr  # Vivado 工程文件
```

## 模块清单

| 文件 | 模块 | 说明 |
| ---- | ---- | ---- |
| DAC904_TOP.v | DAC904_TOP | 顶层模块：时钟分配、各子模块例化、DAC/LED/SPI 接口 |
| PLL_CLK.v | PLL_CLK | 165MHz 时钟生成（例化 pll_165m IP） |
| ROM_Sin.v | ROM_Sin | 正弦波查表（例化 rom_sin IP） |
| ROM_Tri.v | ROM_Tri | 三角波查表（例化 rom_tri IP） |
| add_32bit.v | add_32bit | 32 位相位累加器，取高 12 位作为 ROM 地址 |
| spi.v | spi | SPI 从机接口（同步、收发、MISO 回显） |
| cmd_con.v | cmd_con | 命令解码：波形 / 频率 / 扫频状态机 / 频率计使能 / 软复位 |
| sel_wave.v | sel_wave | 正弦 / 三角 / 方波输出选择 |
| frequency_meter.v | simple_freq_meter | 1s 闸门频率计 |
| seg7_hex8.v | seg7_hex8 | 8 位七段数码管显示 |
| bin2bcd_32.v | bin2bcd_32 | 二进制转 BCD |
| key_con.v | key_con | 原按键控制逻辑（历史版本保留，当前未例化） |
| key_delay.v | key_delay | 原按键消抖逻辑（历史版本保留，当前未例化） |

## IP 核与 ROM 数据

| IP / 数据 | 说明 |
| ---- | ---- |
| ip/pll_165m.xci | 时钟 MMCM，50MHz 输入、165MHz 输出 |
| ip/rom_sin.xci + rom/Sin_Wave.coe | 正弦波 ROM（4096 × 14 位） |
| ip/rom_tri.xci + rom/Tri_Wave.coe | 三角波 ROM（4096 × 14 位） |

IP 的 `.xci` 为定义文件，首次打开工程时 Vivado 会自动生成配套文件。

## 主要引脚

| 信号 | FPGA 引脚 | STM32 侧 | 说明 |
| ---- | ---- | ---- | ---- |
| SCK | G21 | PA8 | SPI 时钟 |
| MOSI | G22 | PA9 | 主机发送 |
| NSS | C22 | PA11 | 片选，低有效 |
| MISO | B22 | PA10 | 主机接收（回显 MOSI） |
| SYS_RST | F15 | — | 复位，低有效 |
| DAC_CLK | A19 | — | DAC 采样时钟（165MHz） |
| DAC_DATA[13:0] | B20 … A16 | — | 14 位 DAC 数据 |
| comparator_out | F19 | — | 比较器反馈，频率计输入 |
| led[3:0] | L13 / M13 / K14 / K13 | — | 波形与频率计状态指示 |

完整时钟、跨时钟域与时序约束说明见 `docs/` 下文档。

## 仿真

`sim/` 下共 3 个测试平台：

- `tb_DAC904_TOP.v` → 顶层整体仿真；
- `tb_spi_cmd.v` → SPI 命令解码仿真；
- `tb_top_spi.v` → SPI 联调 / 顶层集成仿真。

## 重建工程

- `scripts/recreate_project.tcl` 由 Vivado 2022.2 从原工程自动生成，默认 `origin_dir` 指向原工程路径，可用 `--origin_dir <路径>` 覆盖；
- 本仓库按规范重组了目录结构（原工程为 `src/rtl`、`src/sim` 等布局）；如需从本仓库重建，建议在 Vivado 中新建工程后手动添加 `rtl/`、`sim/`、`constrs/`、`ip/`、`rom/` 下的文件，或修改脚本中的路径变量。

## 文档索引

| 文档 | 内容 |
| ---- | ---- |
| `docs/VIVADO_SIGNAL_GENERATOR_SUMMARY.md` | 系统总结：架构、命令协议、扫频规则、时钟与引脚、验证状态（2026-10-28） |
| `docs/PORTING_REPORT.md` | Quartus / Cyclone IV 到 Vivado / Artix-7 的移植记录 |
| `docs/SPI_MERGE_REPORT.md` | SPI 从机合并、历史验证与下载记录 |

## 编码说明

- 工程内 `.v` / `.xdc` 源文件按 GBK(ANSI) 编码保存（原工程即如此），未做转换，保证 Vivado 编辑器中中文注释显示正常；
- Markdown 文档使用 UTF-8；`scripts/encoding.ps1` 提供 UTF-8 与 GBK 互转工具，如需统一转为 UTF-8 可自行使用。
