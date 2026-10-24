# DAC904 波形发生器：Quartus (Cyclone IV) → Vivado 2022.2 移植报告

- 源工程：`transplanted&Information/FPGA_Cyclone_IV_E22_7`（Quartus II 13.0，EP4CE6E22C8）
- 目标工程：`vivado/FPGA_xc7a35t/FPGA_xc7a35t.xpr`，器件 `xc7a35tfgg484-2`
- 顶层：`DAC904_TOP`，综合状态 `synth_design Complete!`（0 error / 0 critical warning）
- 原始移植目录未做任何修改，所有改动只发生在新建的 Vivado 工程内

## 1. Altera 专用依赖排查结论

RTL 源码（`add_32bit.v`、`bin2bcd_32.v`、`DAC904_TOP.v`、`frequency_meter.v`、`key_con.v`、
`key_delay.v`、`seg7_hex8.v`、`sel_wave.v`）是**纯厂商无关 Verilog**，不含任何 Altera
原语（无 `altera_mf`、无 `altddio`、无 `altshift_taps` 等）或 Quartus 专用预处理。全部
厂商相关性只体现在顶层例化的 3 个 Quartus 生成 IP 上。

| 原 Altera IP | 类型 | 关键参数 | 替换为 Xilinx IP | 关键参数 |
|---|---|---|---|---|
| `PLL_CLK` | `altpll`（ALTPLL） | `inclk0` = 50MHz（20000ps），`clk0_multiply_by` = 33，`clk0_divide_by` = 10 → 165MHz | `clk_wiz` v6.0（Clocking Wizard，MMCM） | `PRIM_IN_FREQ` = 50MHz，`CLKOUT1(Requested)` = 165.000MHz |
| `ROM_Sin` | `altsyncram`（ROM: 1-PORT） | 4096 × 14，`outdata_reg_a` = `CLOCK0`，初始化 `Sin_Wave.mif` | `blk_mem_gen` v8.4（Block Memory Generator） | `Single_Port_ROM`，4096 × 14，输出寄存，初始化 `Sin_Wave.coe` |
| `ROM_Tri` | `altsyncram`（ROM: 1-PORT） | 4096 × 14，`outdata_reg_a` = `UNREGISTERED`，初始化 `Tri_Wave.mif` | `blk_mem_gen` v8.4（Block Memory Generator） | `Single_Port_ROM`，4096 × 14，输出寄存，初始化 `Tri_Wave.coe` |

### 1.1 未替换的 Quartus 专用文件（均未导入 Vivado 工程）

| 文件/目录 | 原因 |
|---|---|
| `ip_core/PLL/PLL_CLK.qip`、`.ppf`、`.bsf`、`greybox_tmp/` | Quartus IP 描述，Vivado 无对应概念 |
| `ip_core/ROM/ROM_Sin\*.qip/.bsf`、`ROM_Tri\*.qip/.bsf`、`.mif` | 同上；数据已转成 `.coe` 重新生成 |
| `doc/SDC1.sdc` | Quartus 风格 SDC，含 Vivado 不支持的 `derive_pll_clocks`，且把 `DAC_CLK`/`DAC_DATA` 误当输入时钟约束 |
| `par/*.qsf / *.qpf / db/ / incremental_db/ / output_files/` | Quartus 工程与编译产物 |
| `par/db/PLL_CLK_altpll.v`、`altsyncram_*.tdf`、`PLLJ_PLLSPE_INFO.txt` | Quartus 自动生成文件 |

### 1.2 RTL 保留的厂商无关部分

`PLL_CLK.v` / `ROM_Sin.v` / `ROM_Tri.v` 三个**同名包装模块**放在 `src/rtl/` 下，端口与
Quartus 生成的模块逐位一致，因此 `DAC904_TOP.v` **一行都不用改**。包装模块内部例化
Xilinx IP，端口映射：

| 包装模块端口 | Xilinx IP 端口 | 说明 |
|---|---|---|
| `PLL_CLK.areset` | `pll_165m.reset` | 两者都是高有效；顶层传的是 `!SYS_RST` |
| `PLL_CLK.inclk0` | `pll_165m.clk_in1` | 50MHz |
| `PLL_CLK.c0` | `pll_165m.clk_out1` | 165MHz |
| `ROM_Sin/ROM_Tri.address[11:0]` | `rom_sin/rom_tri.addra[11:0]` | |
| `ROM_Sin/ROM_Tri.clock` | `rom_sin/rom_tri.clka` | |
| `ROM_Sin/ROM_Tri.q[13:0]` | `rom_sin/rom_tri.douta[13:0]` | |

`pll_165m` 的 `locked` 端口未连接（与原设计一致，原 Altera `PLL_CLK` 的 `locked` 也悬空），
为避免无用告警已将该 IP 设为 `USE_LOCKED=false`。

## 2. PLL 参数求解

原 Altera 配置是 ×33 ÷10（50MHz × 33 / 10 = 165MHz）。Clocking Wizard 自动求解出一组
等价 MMCM 参数：

```
DIVCLK_DIVIDE    = 1
CLKFBOUT_MULT_F  = 20.625     -> VCO = 50 × 20.625 / 1 = 1031.25 MHz
CLKOUT0_DIVIDE_F = 6.250      -> clk_out1 = 1031.25 / 6.250 = 165.000 MHz
```

输出频率是**精确的 165.000MHz**（`simple_freq_meter.v` 中 `CLK_FREQ = 165_000_000`
依赖此值）。VCO 1031.25MHz 在 Artix-7 MMCM 允许范围内，综合无相关告警。

## 3. ROM 初始化数据转换

`scripts/mif2coe.ps1` 把 Quartus 的 `.mif` 机械转换为 Vivado 的 `.coe`：

```
transplanted&Information/.../ROM/Sin_Wave.mif  ->  src/rom/Sin_Wave.coe   (4096 项)
transplanted&Information/.../ROM/Tri_Wave.mif  ->  src/rom/Tri_Wave.coe   (4096 项)
```

校验方式：IP 生成后 Vivado 会把 `.coe` 转成 `rom_*.mif`（二进制），
`rom_sin.mif` 首项为 `10000000000000b` = `0x2000`，与 `Sin_Wave.mif` 地址 0 的 `0x2000`
一致；`rom_tri.mif` 首项对应 `Tri_Wave.mif` 地址 0 的 `0x0000`。

## 4. 已知行为差异

1. **三角波相位**：原 `ROM_Sin` 是 `outdata_reg_a = "CLOCK0"`（输出寄存），而 `ROM_Tri`
   是 `UNREGISTERED`（输出直通），两者延迟本来就不一致。Xilinx BRAM ROM 强制寄存输出，
   本工程把两路统一为「地址 + 输出寄存器」的一级寄存读，三角波相对原设计多一个
   165MHz 时钟（约 6ns）的相位延迟。对本应用（固定频率波形发生）无影响；若要严格复刻，
   可把 `ROM_Tri` 换成 `dist_mem_gen`（分布式 RAM，异步读）。
2. **ROM IP 的 OOC 时序约束**：`blk_mem_gen` 生成的 `rom_*_ooc.xdc` 默认写死
   `create_clock -period 20.0`（50MHz），所以顶层综合会提示
   `[Timing 38-316] ... actual clock period '6.061'`——这是**提示性告警**，
   顶层时序分析仍按 165MHz（6.061ns）进行，且 Artix-7 的 BRAM 远快于 165MHz，
   不影响功能。若需要消除该告警，可把两份 `*_ooc.xdc` 里的周期改成 `6.061`。
3. **复位极性**：RTL 端口名有的叫 `rst`、有的叫 `rst_n`，但实际全部按**低有效**使用
   （`add_32bit` 用 `if(!rst)`、`key_con/seg7_hex8/sel_wave` 用 `negedge rst_n`，
   PLL 的 `areset` 接 `!SYS_RST`）。移植后行为与 Quartus 一致，仅命名不统一。

## 5. 发现的其它遗留问题

| 问题 | 说明 | 处理 |
|---|---|---|
| QSF 引用 `../rtl/DAC904.v` | 该文件在源工程中**不存在**（历史残留） | 未导入，无影响 |
| QSF 重复引用 `bin2bcd_32.v` | 同时引用 `par/bin2bcd_32.v` 与 `../rtl/bin2bcd_32.v` | 只导入 `rtl/` 版本 |
| `tb_DAC904_TOP.v` 与顶层端口不匹配 | `KEY_IN` 只有 3 位，缺 `PD/BEEP_EN/comparator_out/a_to_g/an/dp/LED`，且未驱动 `comparator_out` | 已重写为 `src/sim/tb_DAC904_TOP.v` 并设为 `sim_1` 顶层（语法已用 `xvlog` 校验） |
| `SDC1.sdc` 把 `DAC_CLK`/`DAC_DATA` 当输入时钟 | 这两个是输出端口 | 未导入，改用新的 `src/constrs/top.xdc` |
| `simple_freq_meter` 中 `temp_mul` 高位未使用 | 综合报 `Sequential element (temp_mul_reg[4x]) is unused` | 属原设计写法，不影响功能 |

## 6. 新建工程结构

```
vivado/FPGA_xc7a35t/
├─ FPGA_xc7a35t.xpr                      Vivado 工程
├─ PORTING_REPORT.md                     本报告
├─ src/rtl/                              11 个 Verilog 源文件
│   ├─ (原 8 个 RTL, 从移植目录原样复制)
│   ├─ PLL_CLK.v                         altpll 包装 -> clk_wiz
│   ├─ ROM_Sin.v                         altsyncram 包装 -> blk_mem_gen
│   └─ ROM_Tri.v                         altsyncram 包装 -> blk_mem_gen
├─ src/rom/Sin_Wave.coe, Tri_Wave.coe    ROM 初始化数据
├─ src/constrs/top.xdc                   50MHz 时钟约束
├─ src/sim/tb_DAC904_TOP.v               修正后的测试平台
└─ scripts/
    ├─ mif2coe.ps1                       .mif -> .coe 转换脚本
    └─ recreate_project.tcl              一键重建工程的 Tcl 脚本
```

IP 输出产物位于 `FPGA_xc7a35t.srcs/sources_1/ip/<ip>/` 与 `FPGA_xc7a35t.gen/sources_1/ip/<ip>/`。

## 7. 约束

`src/constrs/top.xdc` 只有一条：

```tcl
create_clock -name SYS_CLK -period 20.000 [get_ports SYS_CLK]
```

165MHz 时钟由 MMCM 自动派生，不需要 `derive_pll_clocks`。**引脚约束尚未添加**，
需要黑金 AX7A035B 官方 XDC 后再补 `PACKAGE_PIN` / `IOSTANDARD`。

## 8. 综合结果

```
synth_1: synth_design Complete!   0 Errors, 0 Critical Warnings, 94 Warnings

MMCME2_ADV        : 1   (20.0%)      <- PLL_CLK 的 165MHz 时钟
Block RAM Tile    : 4   ( 8.0%)      <- 两个 4096x14 ROM, 各占 2 个 RAMB36
LUT as Memory     : 0   ( 0.0%)      <- 确认 ROM 没有被退化成 LUT 实现
BUFGCTRL          : 3   ( 9.4%)      <- SYS_CLK + MMCM 反馈 + 165MHz 输出
Slice LUTs        : 3086 (14.8%)
Slice Registers   : 600  ( 1.4%)
DSP48E1           : 4   ( 4.4%)      <- 频率计的 64bit 乘法
```

其余告警均为原设计固有（`PD`/`BEEP_EN` 接常量 0、`dp` 接常量 1、`temp_mul` 高位未用、
并行综合条件未满足），无移植引入的新问题。

## 9. 复现与后续

```powershell
# 打开工程
& "D:\DevEnvironment\Vivado2022.2\Vivado\2022.2\bin\vivado.bat" `
  "D:\project\2026_FPGA-stm32\ce_shi\yi_zhi\vivado\FPGA_xc7a35t\FPGA_xc7a35t.xpr"

# 或从脚本重建（脚本内含源文件路径与 IP 配置）
& "D:\DevEnvironment\Vivado2022.2\Vivado\2022.2\bin\vivado.bat" -mode batch `
  -source "D:\project\2026_FPGA-stm32\ce_shi\yi_zhi\vivado\FPGA_xc7a35t\scripts\recreate_project.tcl"
```

后续待办：

1. 拿到黑金 AX7A035B 的官方 XDC，补引脚约束（`SYS_CLK`、`KEY_IN[3:0]`、`DAC_DATA[13:0]`、
   `DAC_CLK`、`PD`、`BEEP_EN`、`comparator_out`、`a_to_g[6:0]`、`an[7:0]`、`dp`、`LED`）。
2. 补引脚后跑实现（`place_design` → `route_design`）并检查时序。
3. 板级验证 DAC 输出波形、按键调频/换波形、频率计与数码管显示（频率计闸门 1 秒，
   无法在仿真中完整验证）。
