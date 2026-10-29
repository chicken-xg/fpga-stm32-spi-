#include "key.h"
#include "delay.h"

/* 消抖: 连续2次扫描都是同一状态才有效, 每5ms扫一次, 约10ms */
#define DEBOUNCE  2

/* 每个按键一组状态:
 *   xx_ok : 当前是否处于按下状态(1=按下, 0=释放)
 *   xx_cnt: 连续出现相同电平的次数
 * 按键一端接地, GPIO上拉输入, 读到0表示按下 */
static u8 fup_ok = 0, fup_cnt = 0;    /* 频率加      PB5 */
static u8 wsw_ok = 0, wsw_cnt = 0;    /* 波形切换    PB6 */
static u8 fdn_ok = 0, fdn_cnt = 0;    /* 频率减      PB7 */
static u8 f1_ok  = 0, f1_cnt  = 0;    /* 固定加1kHz  PB8 */
static u8 fsd_ok = 0, fsd_cnt = 0;    /* 固定减1kHz  PB9 */
static u8 swp_ok = 0, swp_cnt = 0;    /* 扫频        PB10 */
static u8 rst_ok = 0, rst_cnt = 0;    /* 复位        PB11 */

/* 记录"本次刚按下"的键: 哪个按下, 就把对应位(bit)置1 */
static volatile u8 press;

/* 第一步: 把PB5~PB11配置为上拉输入 */
void KEY_Init(void)
{
    GPIO_InitTypeDef g;

    RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOB, ENABLE);

    g.GPIO_Pin  = KEY_FREQ_UP_PIN|KEY_WAVE_SW_PIN|KEY_FREQ_DOWN_PIN|KEY_FSTEP_UP1_PIN|
                  KEY_FSTEP_DN_PIN|KEY_SWEEP_PIN|KEY_RESET_PIN;
    g.GPIO_Mode = GPIO_Mode_IPU;    /* 上拉输入: 平时高电平, 按下接地变低 */
    g.GPIO_Speed= GPIO_Speed_50MHz;
    GPIO_Init(GPIOB, &g);
}

/* 第二步: 用定时器2每5ms产生一次中断, 中断里扫描按键 */
void KEY_Timer_Init(void)
{
    TIM_TimeBaseInitTypeDef t;
    NVIC_InitTypeDef n;

    RCC_APB1PeriphClockCmd(RCC_APB1Periph_TIM2, ENABLE);

    TIM_TimeBaseStructInit(&t);
    t.TIM_Period       = 4999;      /* 计数4999次产生更新 */
    t.TIM_Prescaler    = 71;        /* 先把72MHz分频72, 得到1MHz */
    t.TIM_ClockDivision= 0;
    t.TIM_CounterMode  = TIM_CounterMode_Up;
    TIM_TimeBaseInit(TIM2, &t);

    TIM_ITConfig(TIM2, TIM_IT_Update, ENABLE);   /* 打开更新中断 */

    n.NVIC_IRQChannel = TIM2_IRQn;
    n.NVIC_IRQChannelPreemptionPriority = 2;
    n.NVIC_IRQChannelSubPriority = 0;
    n.NVIC_IRQChannelCmd = ENABLE;
    NVIC_Init(&n);

    TIM_Cmd(TIM2, ENABLE);          /* 启动定时器 */
}

/* 第三步: 每5ms调用一次, 逐个扫描7个按键 */
void KEY_Scan(void)
{
    /* 频率加 PB5 */
    if(!GPIO_ReadInputDataBit(GPIOB, KEY_FREQ_UP_PIN))   /* 读到0说明按下 */
    {
        if(++fup_cnt >= DEBOUNCE)                   /* 连续2次都是按下, 消抖通过 */
        {
            if(!fup_ok) press |= KEY_FREQ_UP;       /* 上次是释放, 这次才算新按下 */
            fup_cnt = 0;
            fup_ok = 1;                             /* 记住: 现在处于按下 */
        }
    }
    else
    {
        fup_cnt = 0;
        fup_ok = 0;                                 /* 释放, 记住现在没按 */
    }

    /* 波形切换 PB6 */
    if(!GPIO_ReadInputDataBit(GPIOB, KEY_WAVE_SW_PIN))
    {
        if(++wsw_cnt >= DEBOUNCE)
        {
            if(!wsw_ok) press |= KEY_WAVE_SW;
            wsw_cnt = 0;
            wsw_ok = 1;
        }
    }
    else
    {
        wsw_cnt = 0;
        wsw_ok = 0;
    }

    /* 频率减 PB7 */
    if(!GPIO_ReadInputDataBit(GPIOB, KEY_FREQ_DOWN_PIN))
    {
        if(++fdn_cnt >= DEBOUNCE)
        {
            if(!fdn_ok) press |= KEY_FREQ_DOWN;
            fdn_cnt = 0;
            fdn_ok = 1;
        }
    }
    else
    {
        fdn_cnt = 0;
        fdn_ok = 0;
    }

    /* 固定加1kHz PB8 */
    if(!GPIO_ReadInputDataBit(GPIOB, KEY_FSTEP_UP1_PIN))
    {
        if(++f1_cnt >= DEBOUNCE)
        {
            if(!f1_ok) press |= KEY_FSTEP_UP1;
            f1_cnt = 0;
            f1_ok = 1;
        }
    }
    else
    {
        f1_cnt = 0;
        f1_ok = 0;
    }

    /* 固定减1kHz PB9 */
    if(!GPIO_ReadInputDataBit(GPIOB, KEY_FSTEP_DN_PIN))
    {
        if(++fsd_cnt >= DEBOUNCE)
        {
            if(!fsd_ok) press |= KEY_FSTEP_DN;
            fsd_cnt = 0;
            fsd_ok = 1;
        }
    }
    else
    {
        fsd_cnt = 0;
        fsd_ok = 0;
    }

    /* 扫频 PB10 */
    if(!GPIO_ReadInputDataBit(GPIOB, KEY_SWEEP_PIN))
    {
        if(++swp_cnt >= DEBOUNCE)
        {
            if(!swp_ok) press |= KEY_SWEEP;
            swp_cnt = 0;
            swp_ok = 1;
        }
    }
    else
    {
        swp_cnt = 0;
        swp_ok = 0;
    }

    /* 复位 PB11 */
    if(!GPIO_ReadInputDataBit(GPIOB, KEY_RESET_PIN))
    {
        if(++rst_cnt >= DEBOUNCE)
        {
            if(!rst_ok) press |= KEY_RESET;
            rst_cnt = 0;
            rst_ok = 1;
        }
    }
    else
    {
        rst_cnt = 0;
        rst_ok = 0;
    }
}

/* 第四步: 读取本次按下了哪些键(对应位=1), 并清空 */
u8 KEY_GetPress(void)
{
    u8 f = press;
    press = 0;
    return f;
}
