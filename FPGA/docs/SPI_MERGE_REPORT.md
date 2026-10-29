# 波形发生器 + SPI 从机合并报告

- 工程：`vivado/FPGA_xc7a35t/FPGA_xc7a35t.xpr`（Vivado 2022.2，`xc7a35tfgg484-2`）
- 顶层：`DAC904_TOP`
- 来源：波形发生器（原 Quartus/DAC904 工程） + SPI 从机（`SPI_FPGA/.../cs11` 里已验证的位回环方案）
- 结论：**仿真 A/B 全部通过，综合 0 error / 0 critical warning**；引脚锁定与实现由使用者完成

---

## 1. 做了什么

原来的 4 个按键（`key_con` + `key_delay`）控制波形与频率，现在换成 **STM32 通过 SPI 发来的字节命令**：

- FPGA 侧新增 SPI 从机 `spi.v`，沿用 cs11 里那套「位回环」——SCK 每个上升沿把采到的 MOSI 那一位立刻回显到 MISO，
  所以 STM32 端 `g_rx == g_tx` 的判据照旧成立，**LCD 仍然显示"通信成功"，STM32 一行代码都不用改**。
- 新增命令解码器 `cmd_con.v`，把收到的字节翻译成 `sel_wave[1:0]`（波形）、`fre_k[31:0]`（频率字）、`meas_en`（频率计使能）、
  `phase_rst`（相位累加器软复位），接到原来的 ROM/累加器/波形选择/频率计上。
- `DAC904_TOP` 删除 `KEY_IN[3:0]`，新增 `SCK/MOSI/NSS/MISO` 和 4 个 LED 指示。
- ROM、PLL、数码管、频率计、DAC 输出这些原本就正常的部分**一行没改**。

---

## 2. 指令表（STM32 发送的字节 / LCD 上的 4 位字符串）

| 发送 | 功能 | 与原设计对应 |
|---|---|---|
| 0001 (0x01) | 频率 +1 档 | 原 key1 |
| 0010 (0x02) | 换波形：正弦 → 三角 → 方波 → 正弦 | 原 key2 |
| 0011 (0x03) | 频率 −1 档 | 原 key3 |
| 0100 (0x04) | 频率计使能 开/关（上电默认开） | 原 key4 |
| 0101 (0x05) | 频率 +1kHz（固定细调，**本次新增定义**） | 无 |
| 0110 (0x06) | 频率 −1kHz（固定细调，**本次新增定义**） | 无 |
| 1000 (0x08) | 软复位：频率回 1kHz、波形回正弦、使能开、相位累加器清零 | 复位键的"字符串版" |
| 其它 | 忽略，保持当前状态 | — |

档位步进逐条照搬原 `key_con.v`：阈值 260310 / 2603100 / 26031000 / 2603100000，
步长 26031 / 260310 / 2603100 / 26031000；`fre_k = 26031` 即 1kHz，到 100MHz 后回卷到 1kHz，减到底保持 1kHz。

> 0101 / 0110 / 1000 是本次新增的码（原 `key_con` 只有自适应档位，没有固定步进值）。
> 不需要的话把 `cmd_con.v` 里对应 case 删掉即可，其余功能不受影响。

---

## 3. 引脚锁定（已写入 `src/constrs/top.xdc`）

依据《黑金 AX7A035B 开发板用户手册 REV1.0》，全部落在 **J11 排针** 上（J13 在 35T 上不可用）。

| 信号 | 位置 | FPGA ball | IOSTANDARD |
|---|---|---|---|
| `sys_clk_p` / `sys_clk_n` | 板载 200MHz 差分晶振 | R4 / T4 | DIFF_SSTL15 |
| `SYS_RST`（RESET 键，低有效） | 按键 | F15 | LVCMOS33 + PULLUP |
| `KEY4`（自动扫频开关，低有效） | 扩展板 KEY4 | J17 | LVCMOS33 + PULLUP |
| `SCK` / `MOSI` / `NSS` / `MISO` | J11-3/4/5/6 | G21 / G22 / C22 / B22 | LVCMOS33 |
| `comparator_out`（TLV3501 比较器） | J11-7 | F19 | LVCMOS33 |
| `BEEP_EN`（RTL 里恒 0） | J11-9 | D20 | LVCMOS33 |
| `PD` | J11-11 | A18 | LVCMOS33 |
| `DAC_CLK` | J11-12 | A19 | LVCMOS33 |
| `DAC_DATA[13]` … `[0]` | J11-13 … J11-26 | B20 A20 F18 E18 E19 D19 C18 C19 B17 B18 D17 C17 A15 A16 | LVCMOS33 |
| `led[0..3]`（正弦/三角/方波/使能，低电平点亮） | 板载 LED1~LED4 | L13 M13 K14 K13 | LVCMOS33 |
| `LED`（实测频率 ≤1MHz 点亮） | 核心板 LED1 | W5 | LVCMOS15 |

J11 剩余空脚（未锁，留给备用）：8=F20、10=C20、27=B15、28=B16、29=A13、30=A14、
31=E16、32=D16、33=C14、34=C15、35=F16、36=E17。

接线要点：

- 200MHz 差分时钟是板载的，不用外接；顶层 4 分频得到 50MHz 再进 PLL。
- STM32 的 PA8/PA9/PA10/PA11 ↔ J11 的 3/4/5/6，**必须共地**，MISO 漏接会读随机值。
- DAC904 模块：数据 D0~D13 + CLK + PD 对应 J11 的 11~26（见上表），5V 用 J11-2，3.3V 用 39/40，GND 用 1/37/38。

---

## 4. 文件变更

| 文件 | 变更 |
|---|---|
| `src/rtl/spi.v` | **新增**（从 cs11 复制，逻辑未改；时钟由顶层给 165MHz） |
| `src/rtl/cmd_con.v` | **新增**（命令解码器，代替 key_con） |
| `src/rtl/DAC904_TOP.v` | 删 `KEY_IN`，加 SPI/LED 端口，例化 `spi`+`cmd_con`；时钟改为 200MHz 差分输入 + 4 分频；删掉数码管（`seg7_hex8`/`bin2bcd_32`）；`led` 改为低电平点亮 |
| `src/constrs/top.xdc` | 补齐**全部引脚约束** + `create_clock`（5ns 差分时钟）+ 跨时钟域 `set_false_path` + 频率计除法器的多周期约束 + QSPI Flash 配置属性 |
| `src/sim/tb_spi_cmd.v` | **新增**：spi + cmd_con 的仿真（位回环 + 全部指令码） |
| `src/sim/tb_top_spi.v` | **新增**：完整顶层集成仿真（200MHz 差分时钟模型、PLL、波形、频率、led 低有效） |
| `src/sim/tb_DAC904_TOP.v` | **从工程移除**（磁盘保留）：它的端口列表里还有已被删除的 `KEY_IN`，直接跑会报错，已被 `tb_top_spi.v` 取代 |
| `src/rtl/key_con.v` / `key_delay.v` | **从工程移除**（磁盘保留）：不再被例化 |
| `src/rtl/seg7_hex8.v` / `bin2bcd_32.v` | **从工程移除**（磁盘保留）：数码管用不上（板上没有 8 位数码管，J11 也放不下 16 根线） |
| `scripts/recreate_project.tcl` | 同步源文件清单；去掉 `synth_1` 的增量综合检查点 |
| `scripts/encoding.ps1` | **新增**：UTF-8 <-> GBK 编码转换脚本（见第 8 节） |

---

## 5. 关键设计点

1. **时钟链**：板载 200MHz 差分（R4/T4）→ `IBUFDS` → `BUFG` → 2 位计数器 4 分频 →
   `BUFG` 得到 50MHz → 原来的 `pll_165m`（clk_wiz）→ 165MHz。
   板子上没有 50MHz 晶振，所以由 200MHz 分频得到；PLL IP 一行没改，165MHz 仍是精确值。
2. **时钟域**：SPI 从机直接用 `CLK_165M`（PLL 输出），与命令解码器同域，
   所以整条命令链路**没有任何跨时钟域握手**；SCK/MOSI/NSS 由 `spi.v` 内部 3 级同步器处理。
3. **位回环**：`MISO` 在 SCK 上升沿回显刚采到的 MOSI 位，主机在同一个 SCK 高电平期间读回，8 位下来 `rx == tx`。
4. **软复位**：`1000` 除了回默认波形/频率，还会给 `add_32bit` 一个复位脉冲（相位累加器清零，波形从起点重新开始）。
5. **LED 极性**：AX7A035B 的 LED1~LED4（L13/M13/K14/K13）是**低电平点亮**，
   RTL 里 `assign led = ~{...}`；核心板那颗用户 LED（W5，BANK34 1.5V）是高电平点亮，
   `LED` 输出直接接过去表示"实测频率 ≤1MHz"。数码管已从设计里去掉（板上没这个器件）。

---

## 6. 验证结果（本次实际跑的）

### 6.1 仿真 A：`tb_spi_cmd.v`（spi + cmd_con）

把 STM32 的 `SoftSPI_ReadWriteByte()` 逐条翻译成主机模型，SCK 高电平取 100/300/1000ns 三档：

```
位回环 12/12          （4 个码 × 3 档 SCK 高电平，rx 全部等于 tx）
0001 频率+1档        1k -> 2k -> 3k -> 4k        OK
0011 频率-1档        4k -> 3k                    OK
0010 换波形          正弦 -> 三角 -> 方波 -> 正弦 OK
0100 使能开关        开 -> 关 -> 开              OK
0101 / 0110 细调     ±1kHz（到底保持 1kHz）      OK
1111 非法码          状态不变                    OK
1000 软复位          回 1kHz/正弦/使能开, phase_rst 脉冲出现 OK
连发 200 次 0001     跑到 100MHz 后回卷, fre_k 仍是合法档位 OK
==== 结果: 位回环 12/12, 失败项 0 ====   PASS
```

### 6.2 仿真 B：`tb_top_spi.v`（完整顶层，200MHz 差分时钟模型）

```
#1  PLL 锁定, 500us 内 DAC_CLK 翻转 81873 次
#2  led=0110（默认正弦 + 使能开, 低电平点亮）
#3  输出周期 999963ns  -> 1.000 kHz
#4  正弦特征: max_delta=13 LSB, 不同增量 13 种, min=0 max=16383
#5  led=0110
#6  发 0001×3 后周期 249994ns -> 4.000 kHz
#7  led=0101（三角）   #8 周期 249988ns -> 4.000 kHz
#9  三角特征: max_delta=8 LSB（线性斜坡）
#10 led=0011（方波）   #11 周期 249988ns -> 4.000 kHz
#12 方波特征: max_delta=16383, 只有 0 / 16383 两个电平
#13/#14 0100 使能关/开: led=1011 -> 0011
#15 1000 软复位后 led=0110
#16 周期 999964ns -> 1.000 kHz  #17 回到 1kHz 正弦
#18 顶层 MISO 回环正常（STM32 会显示"通信成功"）
==== 结果: 失败项 0 ====   PASS
```

### 6.3 综合 / 实现 / 比特流（`synth_1` + `impl_1`）

```
Synthesis            : 0 errors, 0 critical warnings, 92 warnings
Implementation       : DRC 0 errors（43 条全是 DSP 流水/异步复位的提示性告警, 无 I/O 相关违例）
Timing (routed)      : WNS = +0.542ns  TNS = 0.000  WHS = +0.183ns  THS = 0.000
                       （时序收敛；clk_out1_pll_165m 6.061ns, sys_clk_p 5.000ns）
write_bitstream      : Complete

实现后资源:
Slice LUTs        : 2722 (13.09%)
Slice Registers   :  344 ( 0.83%)
Block RAM Tile    :    4 ( 8.00%)   <- 两个 4096x14 ROM
DSP48E1           :    4 ( 4.44%)   <- 频率计乘法
Bonded IOB        :   30 (12.00%)   <- 全部 FIXED, 无未约束 IO
MMCME2_ADV        :    1, BUFGCTRL 4

比特流: FPGA_xc7a35t.runs/impl_1/DAC904_TOP.bit
```

说明：原设计里频率计的 64bit/32bit 除法被综合成一大团组合逻辑（数据路径 >130ns），
第一次实现时时序不收敛（WNS −141ns）。因为该结果一秒才用一次（闸门 1s），
在 `top.xdc` 里给这块逻辑加了多周期约束，功能不变、时序随后收敛。

---

## 7. 上板要做的

1. **下载**：连 JTAG，直接用 Vivado Hardware Manager 下载 `impl_1/DAC904_TOP.bit`（不用烧 Flash）。
   要固化就把 bit 转成 .mcs 或直接用 Vivado 的 "Program Configuration Memory"（QSPI 配置属性已经写进 XDC）。
2. **接线**：按下表把 DAC904 模块插到 J11（或飞线），并接 5V/3.3V/GND；
   STM32 的 PA8/PA9/PA11/PA10 ↔ J11 的 3/4/5/6，**必须共地**，MISO 漏接会读随机值、判"通信失败"。
3. **验证顺序**：上电看 LED —— 默认应该是「正弦」(led[0]) + 使能 (led[3]) 两个灯亮（低电平点亮）；
   STM32 按一下发 0001，输出频率变成 2kHz（示波器看 DAC 输出）；发 0010 依次切三角/方波；
   发 0100 使能灯灭；发 1000 回到 1kHz 正弦。
4. STM32 侧**不用改**就能测：它现有 4 个键发的 0001/0010/0011/0100 分别对应
   频率+ / 换波形 / 频率− / 使能开关（按键丝印名 POWER/TRI/SQUARE/SINE 与功能不再一一对应，LCD 上显示的 4 位码是对的）。
   想用 0101/0110/1000 再在 STM32 上加键发对应字节即可。
5. 注意：`R14` 是**以太网 PHY 的复位**（手册 31 页），不要往那接按钮；复位用的是板上 RESET 键 (F15)。

---

## 8. 中文注释与文件编码（重要）

- 本工程的 **HDL / 约束 / Tcl 源文件统一保存成 GBK（CP936，中文 Windows 的 ANSI）**。
  原因：Vivado 的文本编辑器（以及记事本、Keil）都按 Windows 系统 ANSI 解码文件，
  UTF-8 文件里的中文在这些工具里会显示成乱码（例如「命令解码器」变成「鍛戒护瑙ｇ爜鍣?」）。
- HDL 文件**不能**加 UTF-8 BOM：实测 Vivado 的 `xvlog` 会直接报
  `syntax error near 'non-printable character with the hex value 0xef'`，
  所以「Vivado 里显示正常」+「能综合/仿真」的唯一组合是 **GBK 无 BOM**。
- 用 Codex / apply_patch 改这些文件之前，要先转成 UTF-8，改完再转回 GBK（脚本已经准备好）：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\encoding.ps1 -To utf8   # 改代码前
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\encoding.ps1 -To gbk    # 改完、交给 Vivado 前
```

- 报告 / 文档类文件（`*.md`）保持 UTF-8，Markdown 阅读器和 Codex 界面都按 UTF-8 渲染。
- 代码注释一律用简体中文（已写进 `ce_shi/AGENTS.md`，以后新写的代码同样遵守）。

## 9. 备注

- 回滚点：`vivado/FPGA_xc7a35t还没有spi.zip`（改动前的完整工程快照）。
- 本次在工程目录下留下两个临时目录 `.xsim_a` / `.xsim_b`（命令行仿真用的编译产物，约 5MB），可直接删除。
- 在 GUI 里跑仿真：`sim_1` 的顶层目前是 `tb_spi_cmd`（快）；要看完整顶层就把 sim 顶层切成 `tb_top_spi` 再 Run Simulation。

## 10. 2026-10-26 扫频升级与最终下载（最新）

### 10.1 KEY4 扫频行为

- KEY4（J17）低有效，使用 165MHz 时钟进行 3 级同步和约 20ms 消抖。
- 第一次按下：启动扫频并从 1kHz 重新开始。
- 扫频步进固定为 `26031`（约 1kHz），每 `165000000` 个 165MHz 周期增加一步，即每 1s 增加约 1kHz。
- 扫到 100MHz 后回到 1kHz 并继续循环，一轮约 27.8 小时。
- 第二次按下：停止扫频并保持当前频率；再次按下会重新从 1kHz 开始。
- SPI 频率增减、固定 ±1kHz 或软复位命令会停止扫频；换波形和频率计开关命令不会中断扫频。
- DAC、ROM、波形选择和频率计功能保持不变。

### 10.2 SPI 加固

- 保持 STM32 端 `g_rx == g_tx` 协议，不修改 STM32 程序。
- MISO 在片选有效时直接输出经过 3 级同步的 MOSI 位，在 SCK 上升沿前已经稳定；
  片选无效时 MISO 为低电平。
- 物理线序仍为 PA8→G21、PA9→G22、PA11→C22、PA10←B22，并必须共地。

### 10.3 仿真结果

```
tb_spi_cmd:
  MISO 空闲电平             OK
  SPI 位回环                68/68
  KEY4 短按滤除             OK
  第一次按键从 1kHz 开始    OK
  1kHz 固定步进            26031 -> 52062 -> 78093
  第二次按键停止并保持      OK
  再次按键从 1kHz 重启      OK
  波形/频率计命令不中断扫频 OK
  手动频率命令停止扫频      OK
  软复位、原有命令、非法码  OK
  100MHz 回卷到 1kHz        OK
  结果: 失败项 0, PASS

tb_top_spi:
  PLL、DAC、三种波形、频率计、SPI 回环原有功能  OK
  KEY4 启动/1kHz 步进/停止保持/重新启动         OK
  结果: 22 项检查, 失败项 0, PASS
```

### 10.4 综合、实现与引脚

```
Synthesis       : 0 errors, 0 critical warnings, 92 warnings
Implementation  : 0 errors, 0 critical warnings
DRC             : 0 errors, 43 warnings (DSP 流水/异步复位建议, 无 I/O 错误)
Timing          : WNS = +0.248ns, TNS = 0.000ns
                  WHS = +0.109ns, THS = 0.000ns
                  All user specified timing constraints are met
Resource        : Slice LUTs 2764 (13.29%)
                  Slice Registers 412 (0.99%)
                  Block RAM Tile 4 (8.00%)
                  DSP48E1 4 (4.44%)
                  Bonded IOB 31 (12.40%, 31/31 FIXED)
KEY4            : J17, LVCMOS33, INPUT, PULLUP, FIXED
```

### 10.5 最终比特流与下载状态

```
Bitstream : FPGA_xc7a35t.runs/impl_1/DAC904_TOP.bit
Size      : 2192118 bytes
SHA256    : 78AD1390EF4397C1E0791565E840D97EA1265C823E78077B8F9F8C2F6F30F0B8
Download  : JTAG SRAM 下载成功, 未烧写 QSPI Flash
DONE      : 1
EOS       : 1
```

下载后刷新 HW Device，设备仍保持已编程状态。板上最终确认时，上电默认应为 1kHz 正弦波；
按下 KEY4 后观察频率逐步增加，再按一次应保持当前频率。
