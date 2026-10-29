# STM32_CGMCU — STM32 控制固件（v2.0 最终版，标准库）

## 工程概况

| 项目 | 内容 |
| ---- | ---- |
| 工程名称 | STM32_CGMCU（Keil MDK 工程） |
| 芯片型号 | STM32F103C8T6（LQFP48，中等容量） |
| 固件库 | STM32F10x 标准外设库（非 HAL） |
| 编译工具 | Keil MDK-ARM（ARMCC） |
| 系统时钟 | 72MHz（`SystemInit()`，HSE + PLL×9） |
| 启动文件 | `CORE/startup_stm32f10x_md.s` |

## 功能简述

STM32 作为 SPI 主机，通过按键操作并在本地 TFT 上显示状态，向 FPGA 下发 8 位命令字节：

- 7 个按键完成频率升降、波形切换、固定 ±1kHz、自动扫频、软复位；
- 软件 SPI（GPIO 模拟，Mode0、MSB-first、8 位）与 FPGA 从机通信，同时回读 FPGA 返回字节做回环校验；
- ST7735 1.8 寸 TFT（128 × 160）实时显示：当前波形、频率（Hz）、扫频开关、通信成功 / 失败、最近下发命令的 4 位二进制；
- TIM2 每 5ms 中断一次，完成按键扫描与扫频计时（200 次 = 1s）；
- 上电默认：正弦波、1kHz，先向 FPGA 发送 `0x08` 复位命令同步两侧状态。

## 按键与命令映射

| 按键引脚 | 功能 | 下发命令 | 二进制 |
| ---- | ---- | ---- | ---- |
| PB5 | 频率升高一档（自适应步进） | `0x01` | `0001` |
| PB6 | 波形循环切换（正弦 → 三角 → 方波） | `0x02` | `0010` |
| PB7 | 频率降低一档 | `0x03` | `0011` |
| PB8 | 频率固定 +1kHz | `0x05` | `0101` |
| PB9 | 频率固定 −1kHz | `0x06` | `0110` |
| PB10 | 启动自动扫频（1kHz/s，从 1kHz 开始） | `0x07` | `0111` |
| PB11 | 软复位（正弦 + 1kHz，停止扫频） | `0x08` | `1000` |

按键为内部上拉、低电平有效；`0x04`（频率计开关）由 FPGA 内部命令集支持，本固件未单独绑定按键。

### 频率步进（STM32 本地状态同步用）

- 升档：`<10kHz` 加 1kHz；`<100kHz` 加 10kHz；`<1MHz` 加 100kHz；`<100MHz` 加 1MHz；超出回 1kHz；
- 降档反向；固定 ±1kHz 命令直接增减 1kHz，到边界回卷 / 钳位到 1kHz；
- 扫频运行中收到手动频率命令或复位命令时，STM32 本地同步停止扫频。

## 引脚分配

### 与 FPGA 通信（软件 SPI，`HA/MYSPI.c`）

| STM32 引脚 | 功能 | 连接 FPGA |
| ---- | ---- | ---- |
| PA8 | SPI_SCK | G21 |
| PA9 | SPI_MOSI | G22 |
| PA10 | SPI_MISO | B22 |
| PA11 | SPI_CS（NSS，低有效） | C22 |

### ST7735 TFT 显示屏（`HARDWARE/LCD/lcd.c`，软件 SPI）

| STM32 引脚 | 功能 |
| ---- | ---- |
| PA0 | LCD_SCL（SCLK） |
| PA1 | LCD_SDA（MOSI） |
| PA2 | LCD_RST（RES） |
| PA3 | LCD_DC（数据 / 命令选择） |
| PA4 | LCD_CS |
| PA5 | LCD_BLK（背光） |

### 按键（`HARDWARE/KEY/key.c`）

PB5 ～ PB11，内部上拉输入，低电平按下，详见上表。

## 目录结构

```
STM32/
├── USER/                        # 工程入口与用户代码
│   ├── main.c                   # 主程序：初始化、按键处理、命令下发、LCD 刷新、TIM2 中断
│   ├── stm32f10x_it.c / .h      # 中断服务例程（本工程 TIM2 中断在 main.c 中实现）
│   ├── system_stm32f10x.c / .h  # 系统时钟与启动级代码
│   ├── stm32f10x_conf.h          # 标准库配置头文件
│   ├── STM32_CGMCU.uvprojx       # Keil 工程文件
│   ├── STM32_CGMCU.uvoptx        # Keil 工程选项
│   ├── EventRecorderStub.scvd    # 事件记录桩文件
│   └── DebugConfig/              # Keil 调试配置
├── CORE/                        # 内核头文件与启动文件
│   ├── core_cm3.c / core_cm3.h
│   └── startup_stm32f10x_md.s
├── HA/                          # 自定义软件 SPI 驱动
│   ├── MYSPI.c / MYSPI.h
├── HARDWARE/
│   ├── KEY/                     # 按键扫描（key.c / key.h）
│   └── LCD/                     # ST7735 驱动（lcd.c / lcd.h / lcdfont.h / pic.h）
├── STM32F10x_FWLib/             # STM32F10x 标准外设库
│   ├── inc/                     # 23 个外设头文件
│   └── src/                     # 23 个外设源文件
└── SYSTEM/                      # 系统支持层
    ├── delay/                   # 延时（delay.c / delay.h）
    ├── sys/                     # 类型定义与常用宏（sys.c / sys.h）
    └── usart/                   # USART1 初始化与 printf 重定向（本工程主流程未调用）
```

## 编译与下载

1. Keil MDK 打开 `USER/STM32_CGMCU.uvprojx`；
2. 直接编译（工程已包含上表所列全部源文件与库文件），生成 `.axf` 后通过 ST-Link / J-Link 下载；
3. 本仓库未归档编译产物（`Objects/`、`Listings/`、`.hex` / `.axf` 均已剔除），首次使用需在本地重新编译生成固件。

> 工程头文件搜索路径中保留了模板遗留的 `HARDWARE/DHT11`、`HARDWARE/LED` 空目录引用，不影响编译；标准库仅加入工程实际使用的 `misc`、`gpio`、`rcc`、`tim`、`usart` 五个源文件。

## 代码说明

- `main.c`：维护本地 `g_freq` / `g_wave` / `g_sweep_on` 状态，按键事件触发对应命令下发；`SPI_SendCmd()` 拉低 CS → 收发一字节 → 拉高 CS；`LCD_Refresh()` 刷新五行显示；
- `HARDWARE/KEY/key.c`：TIM2 5ms 周期扫描，连续两次同状态确认消抖，事件以位掩码存入 `press`，`KEY_GetPress()` 一次性读取并清零；
- `HA/MYSPI.c`：GPIO 模拟 SPI，SCK 空闲低电平（Mode0），先送 / 收最高位；
- 源码为 GBK(ANSI) 编码保存，Keil 中直接打开中文注释正常，请勿在编辑器中强制转码。
