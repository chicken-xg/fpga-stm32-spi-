# fpga-stm32-spi-

2026 年 FPGA 嵌入式比赛开源项目：STM32 通过 SPI 控制 FPGA（黑金 AX7A035B），驱动高速 DAC904 输出正弦波/三角波/方波。

## 系统架构

```
STM32(F103C8T6) --SPI--> FPGA(XC7A35T) --14位并行--> DAC904(165MSPS) --> 波形输出
```

## 目录说明

| 目录 | 说明 |
| ---- | ---- |
| FPGA/ | Vivado 工程：RTL 源码、仿真、约束、IP、比特流 |
| STM32/ | Keil 固件：SPI 通信程序、CubeMX 工程 |
| Hardware/ | 硬件组成文本说明 |

各部分详细介绍见对应目录下的 README.md。
