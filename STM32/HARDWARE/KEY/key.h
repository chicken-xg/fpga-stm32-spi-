#ifndef __KEY_H
#define __KEY_H
#include "sys.h"

/* 按键引脚定义 (PB5~PB11, 按下为低电平) */
#define KEY_FREQ_UP_PIN   GPIO_Pin_5
#define KEY_WAVE_SW_PIN   GPIO_Pin_6
#define KEY_FREQ_DOWN_PIN GPIO_Pin_7
#define KEY_FSTEP_UP1_PIN GPIO_Pin_8
#define KEY_FSTEP_DN_PIN  GPIO_Pin_9
#define KEY_SWEEP_PIN     GPIO_Pin_10
#define KEY_RESET_PIN     GPIO_Pin_11

/* 按键事件位标志(与 main.c 中 SPI 命令对应) */
#define KEY_FREQ_UP     0x01   /* PB5  频率加计数  -> 命令 0001 */
#define KEY_WAVE_SW     0x02   /* PB6  波形切换    -> 命令 0010 */
#define KEY_FREQ_DOWN   0x04   /* PB7  频率减计数  -> 命令 0011 */
#define KEY_FSTEP_UP1   0x08   /* PB8  固定加1kHz  -> 命令 0101 */
#define KEY_FSTEP_DN    0x10   /* PB9  固定减1kHz  -> 命令 0110 */
#define KEY_SWEEP       0x20   /* PB10 扫频(1kHz/s)-> 命令 0111 */
#define KEY_RESET       0x40   /* PB11 复位(正弦波+1kHz) -> 命令 1000 */

void KEY_Init(void);          /* 按键IO初始化 */
void KEY_Timer_Init(void);    /* TIM2定时器初始化(5ms中断, 用于扫描) */
void KEY_Scan(void);          /* 按键扫描, 在TIM2中断里调用 */
u8   KEY_GetPress(void);      /* 获取一次按键事件, 返回位标志 */

#endif
