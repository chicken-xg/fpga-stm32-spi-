# SPI_1 — STM32 固件工程（与 FPGA SPI 通信）

## 工程概况

| 项目 | 内容 |
| ---- | ---- |
| 工程名称 | SPI_1 |
| 芯片型号 | STM32F103C8T6（LQFP48） |
| 生成工具 | STM32CubeMX（固件包 STM32Cube FW_F1 V1.8.5） |
| 编译工具 | Keil MDK-ARM |
| 系统时钟 | 72MHz（HSE 外部晶振 + PLL×9，AHB=72MHz / APB1=36MHz / APB2=72MHz） |
| 烧录固件 | `MDK-ARM/SPI_1/SPI_1.hex` |

## 功能简述

当前固件为 **SPI 通信验证/调试程序**：

- SPI1 配置为全双工主机，与 FPGA 侧 SPI 从机（`spi.v`）通信；
- 主循环：SPI 空闲时拉低 PA4（片选）接收 1 字节，再发送 1 字节（数据 0/1/2 循环递增），随后拉高片选；
- USART1 通过 printf 输出收发结果（`fputc` 已重定向到 USART1），用于串口调试；
- 每轮循环 `HAL_Delay(500)`。

## 引脚分配（来自 SPI_1.ioc）

| 引脚 | 功能 |
| ---- | ---- |
| PA5 | SPI1_SCK |
| PA6 | SPI1_MISO |
| PA7 | SPI1_MOSI |
| PA4 | GPIO_Output，片选 CS（低有效） |
| PA9 | USART1_TX |
| PA10 | USART1_RX |
| PD0 / PD1 | HSE 外部晶振 |
| PC14 / PC15 | LSE 外部晶振 |

> 注意：FPGA 顶层（DAC904_TOP.v）注释中标注的 STM32 侧引脚为 PA8(SCK)/PA9(MOSI)/PA11(NSS)/PA10(MISO)，与本工程 .ioc 配置（PA5/PA6/PA7/PA4）不一致，疑似改版遗留，实际接线以硬件为准，归档时未做改动。

## 目录结构

```
SPI_1/
├── Core/                        # 应用代码（CubeMX 生成 + 用户代码）
│   ├── Inc/                     # main.h / spi.h / usart.h / gpio.h / 中断头文件
│   └── Src/                     # main.c / spi.c / usart.c / gpio.c / stm32f1xx_it.c 等
├── Drivers/
│   ├── STM32F1xx_HAL_Driver/    # HAL 驱动源码（全量保留，Inc + Src + Legacy）
│   └── CMSIS/
│       ├── Include/             # CMSIS 内核头文件
│       ├── Core/Include/        # CMSIS 内核头文件（新版路径，与 Include 内容一致）
│       └── Device/ST/STM32F1xx/Include/   # stm32f1xx 器件头文件
├── MDK-ARM/
│   ├── SPI_1.uvprojx            # Keil 工程文件
│   ├── SPI_1.uvoptx             # Keil 工程选项
│   ├── startup_stm32f103xb.s    # 启动文件
│   ├── RTE/                     # Keil RTE 组件头文件
│   ├── DebugConfig/             # 调试配置
│   └── SPI_1/SPI_1.hex          # 编译产物（固件）
├── SPI_1.ioc                    # CubeMX 工程配置
└── .mxproject                   # CubeMX 工程辅助文件
```

## 使用说明

- **编译**：Keil MDK 打开 `MDK-ARM/SPI_1.uvprojx`，直接编译下载；
- **重新生成**：STM32CubeMX 打开 `SPI_1.ioc` 可重新生成工程；
- **裁剪说明**：原工程 `Drivers/CMSIS` 包含 DSP、NN、RTOS、Lib 等本工程未使用的组件（约 60MB），归档时已剔除，仅保留构建所需的头文件；HAL 驱动按原样全量保留。

## 代码文件清单（Core/Src）

| 文件 | 说明 |
| ---- | ---- |
| main.c | 主程序：系统时钟配置、SPI 收发循环、printf 重定向 |
| spi.c | SPI1 初始化（全双工主机） |
| usart.c | USART1 初始化 |
| gpio.c | GPIO 初始化（PA4 片选等） |
| stm32f1xx_it.c | 中断服务例程 |
| stm32f1xx_hal_msp.c | 外设 MSP 初始化 |
| system_stm32f1xx.c | 系统时钟初始化 |
