# FPGA_xc7a35t — DAC904 波形发生器工程

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

基于 DAC904 的双通道（DAC 数据 14 位）波形发生器：

- 输出波形：正弦波 / 三角波 / 方波，由波形选择逻辑控制；
- 采样时钟：板载 200MHz 差分时钟内部 4 分频得 50MHz，经 PLL 产生 165MHz 采样时钟；
- 波形数据：正弦、三角波通过 ROM 查表输出（`.coe` 初始化）；
- 控制接口：SPI 从机与 STM32 通信（SCK=PA8、MOSI=PA9、NSS=PA11 低有效、MISO=PA10），取代原 4 按键方案；
- 辅助功能：频率计（`simple_freq_meter`）、8 位七段数码管显示、蜂鸣器（BEEP_EN）、LED 波形指示；
- 顶层注释注明 DAC904 输出电压转换公式：`(16383 - DAC_DATA) × (6V / 16383)`。

## 目录结构

```
FPGA/
├── rtl/          # RTL 源码（13 个 .v）
├── sim/          # 仿真测试平台（3 个 tb_*.v）
├── constrs/      # 管脚约束 top.xdc
├── ip/           # IP 核定义（pll_165m / rom_sin / rom_tri 的 .xci）
├── rom/          # ROM 初始化数据（Sin_Wave.coe / Tri_Wave.coe）
├── scripts/      # 辅助脚本（recreate_project.tcl / encoding.ps1 / mif2coe.ps1）
├── docs/         # 开发报告（PORTING_REPORT.md / SPI_MERGE_REPORT.md）
├── output/       # 综合实现产物（DAC904_TOP.bit）
└── FPGA_xc7a35t.xpr  # Vivado 工程文件
```

## 模块清单

| 文件 | 模块 | 说明 |
| ---- | ---- | ---- |
| DAC904_TOP.v | DAC904_TOP | 顶层模块 |
| PLL_CLK.v | PLL_CLK | 165MHz 时钟生成（例化 pll_165m IP） |
| ROM_Sin.v | ROM_Sin | 正弦波查表（例化 rom_sin IP） |
| ROM_Tri.v | ROM_Tri | 三角波查表（例化 rom_tri IP） |
| spi.v | spi | SPI 从机接口 |
| cmd_con.v | cmd_con | 命令解析 |
| sel_wave.v | sel_wave | 波形选择 |
| frequency_meter.v | simple_freq_meter | 频率计 |
| seg7_hex8.v | seg7_hex8 | 8 位七段数码管显示 |
| bin2bcd_32.v | bin2bcd_32 | 二进制转 BCD |
| add_32bit.v | add_32bit | 32 位加法器 |
| key_con.v | key_con | 按键控制（原按键方案，源码保留） |
| key_delay.v | key_delay | 按键消抖 |

## IP 核与 ROM 数据

| IP / 数据 | 说明 |
| ---- | ---- |
| ip/pll_165m.xci | 时钟 PLL，产生 165MHz |
| ip/rom_sin.xci + rom/Sin_Wave.coe | 正弦波 ROM |
| ip/rom_tri.xci + rom/Tri_Wave.coe | 三角波 ROM |

IP 的 `.xci` 为定义文件，首次打开工程时 Vivado 会自动生成配套文件。

## 仿真

`sim/` 下共 3 个测试平台，对应模块名：

- `tb_DAC904_TOP.v` → tb_DAC904_TOP（顶层整体仿真）
- `tb_spi_cmd.v` → tb_spi_cmd（SPI 命令仿真）
- `tb_top_spi.v` → tb_top_spi（SPI 联调仿真）

## 重建工程

- `scripts/recreate_project.tcl` 由 Vivado 2022.2 从原工程自动生成，默认 `origin_dir` 指向原工程路径，可用 `--origin_dir <路径>` 覆盖；
- 本仓库按规范重组了目录结构（原工程为 `src/rtl`、`src/sim` 等布局），如需从本仓库重建，建议在 Vivado 中新建工程后手动添加 `rtl/`、`sim/`、`constrs/`、`ip/`、`rom/` 下的文件，或修改脚本中的路径变量。

## 编码说明

- 工程内 `.v` / `.xdc` 源文件按 GBK(ANSI) 编码保存（原工程即如此），未做转换，保证 Vivado 编辑器中中文注释显示正常；
- `scripts/encoding.ps1` 提供 UTF-8 与 GBK 互转工具，如需统一转为 UTF-8 可自行使用。
