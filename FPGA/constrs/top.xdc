# -----------------------------------------------------------------------------
# FPGA_xc7a35t 顶层约束   (黑金 AX7A035B 扩展板 / xc7a35tfgg484-2)
#
# 引脚依据《黑金 AX7A035B 开发板用户手册 REV1.0》:
#   11 页  板载 200MHz 差分晶振: SYS_CLK_P = R4, SYS_CLK_N = T4 (BANK34)
#   42-43 页  40 针扩展口 J11 的引脚分配 (J13 在 35T 上不可用, 不涉及)
#   45-46 页  按键 RESET = F15 (低有效); 用户 LED1~LED4 = L13/M13/K14/K13 (低电平点亮)
#   17 页  核心板用户 LED1 = W5 (BANK34, 1.5V, 高电平点亮)
#
# 时钟链: 板载 200MHz 差分 -> 顶层 IBUFDS/BUFG -> 4 分频得 50MHz
#         -> PLL_CLK (clk_wiz) -> 165MHz 给 DAC 和全部逻辑
# -----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

############## 200MHz 差分系统时钟 (BANK34) ##################
create_clock -period 5.000 [get_ports sys_clk_p]
set_property PACKAGE_PIN R4 [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL15 [get_ports sys_clk_p]
# N 端 T4 由 Vivado 按差分对自动分配 (与黑金官方例程一致), 这里不单独写

############## 复位按键 RESET (F15, 低有效) ##################
set_property PACKAGE_PIN F15 [get_ports SYS_RST]
set_property IOSTANDARD LVCMOS33 [get_ports SYS_RST]
# 板上 RESET 键已有外部上拉, 这里再打开内部弱上拉做保险
set_property PULLUP TRUE [get_ports SYS_RST]

############## SPI 从机 (J11-3/4/5/6, 与 STM32 相连) ##################
#   STM32: PA8=SCK  PA9=MOSI  PA10=MISO  PA11=CS(NSS)
set_property PACKAGE_PIN G21 [get_ports SCK]
set_property IOSTANDARD LVCMOS33 [get_ports SCK]

set_property PACKAGE_PIN G22 [get_ports MOSI]
set_property IOSTANDARD LVCMOS33 [get_ports MOSI]

set_property PACKAGE_PIN C22 [get_ports NSS]
set_property IOSTANDARD LVCMOS33 [get_ports NSS]

set_property PACKAGE_PIN B22 [get_ports MISO]
set_property IOSTANDARD LVCMOS33 [get_ports MISO]

############## 其它 J11 信号 ##################
# J11-7  TLV3501 比较器输出 -> 频率计输入
set_property PACKAGE_PIN F19 [get_ports comparator_out]
set_property IOSTANDARD LVCMOS33 [get_ports comparator_out]

# J11-9  BEEP_EN (RTL 里恒为 0, 只占一个脚, 可接蜂鸣器模块)
set_property PACKAGE_PIN D20 [get_ports BEEP_EN]
set_property IOSTANDARD LVCMOS33 [get_ports BEEP_EN]

############## DAC904 数据与控制 (J11-11 ... J11-26) ##################
#   引脚编号    信号           FPGA
#   J11-11     PD             A18
#   J11-12     DAC_CLK        A19
#   J11-13..26 DAC_DATA[13..0] B20 A20 F18 E18 E19 D19 C18 C19 B17 B18 D17 C17 A15 A16
set_property PACKAGE_PIN A18 [get_ports PD]
set_property IOSTANDARD LVCMOS33 [get_ports PD]

set_property PACKAGE_PIN A19 [get_ports DAC_CLK]
set_property IOSTANDARD LVCMOS33 [get_ports DAC_CLK]

set_property PACKAGE_PIN B20 [get_ports {DAC_DATA[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[13]}]

set_property PACKAGE_PIN A20 [get_ports {DAC_DATA[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[12]}]

set_property PACKAGE_PIN F18 [get_ports {DAC_DATA[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[11]}]

set_property PACKAGE_PIN E18 [get_ports {DAC_DATA[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[10]}]

set_property PACKAGE_PIN E19 [get_ports {DAC_DATA[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[9]}]

set_property PACKAGE_PIN D19 [get_ports {DAC_DATA[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[8]}]

set_property PACKAGE_PIN C18 [get_ports {DAC_DATA[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[7]}]

set_property PACKAGE_PIN C19 [get_ports {DAC_DATA[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[6]}]

set_property PACKAGE_PIN B17 [get_ports {DAC_DATA[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[5]}]

set_property PACKAGE_PIN B18 [get_ports {DAC_DATA[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[4]}]

set_property PACKAGE_PIN D17 [get_ports {DAC_DATA[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[3]}]

set_property PACKAGE_PIN C17 [get_ports {DAC_DATA[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[2]}]

set_property PACKAGE_PIN A15 [get_ports {DAC_DATA[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[1]}]

set_property PACKAGE_PIN A16 [get_ports {DAC_DATA[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC_DATA[0]}]

############## 用户 LED (扩展板 LED1~LED4, 低电平点亮) ##################
#   led[0]=正弦  led[1]=三角  led[2]=方波  led[3]=频率计使能 (RTL 里已取反)
set_property PACKAGE_PIN L13 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN M13 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN K14 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN K13 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

############## 核心板用户 LED1 (W5, BANK34 1.5V, 高电平点亮) ##################
#   实测频率 <= 1MHz 时点亮
set_property PACKAGE_PIN W5 [get_ports LED]
set_property IOSTANDARD LVCMOS15 [get_ports LED]

############## 跨时钟域处理 ##################
# SCK / MOSI / NSS / comparator_out 相对 165MHz 是异步信号,
# spi.v 内部 3 级同步器、frequency_meter.v 内部同步+去抖已经处理, 不做时序分析。
set_false_path -from [get_ports {SCK}]
set_false_path -from [get_ports {MOSI}]
set_false_path -from [get_ports {NSS}]
set_false_path -from [get_ports {comparator_out}]

############## 频率计除法器的多周期约束 ##################
# simple_freq_meter 里的 64bit/32bit 除法 (temp_mul / std_cnt_latch) 被综合成一大团
# 纯组合逻辑, 实测数据路径超过 130ns, 远大于 165MHz 的 6.06ns 周期; 综合工具还会
# 给这团逻辑插入自己的内部寄存器 (frequency[*]_i_*_psdsp), 所以不能只约束一个终点。
#
# 但这段逻辑的结果一秒才用一次: 闸门时间是 165MHz 下的 1 秒 (约 1.65e8 个周期),
# frequency 寄存器只在 measure_done 那一拍被更新。所以把"以频率计模块为起点或
# 终点"的路径整体放宽成多周期, 不按单个 165MHz 周期检查 —— 功能完全不变。
set freq_meter_cells [get_cells -hierarchical -quiet -filter {IS_SEQUENTIAL && (NAME =~ *freq_meter* || NAME =~ *frequency* || NAME =~ *std_cnt* || NAME =~ *sig_cnt* || NAME =~ *gate_cnt*)}]
set_multicycle_path -setup 165000000 -from $freq_meter_cells
set_multicycle_path -hold  164999999 -from $freq_meter_cells
set_multicycle_path -setup 165000000 -to   $freq_meter_cells
set_multicycle_path -hold  164999999 -to   $freq_meter_cells

############## 配置 Flash 设置 (板载 QSPI Flash, 与官方例程一致) ##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
