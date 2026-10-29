#include "delay.h"
#include "sys.h"
#include "lcd.h"
#include "MYSPI.h"
#include "key.h"

/* =====================================================================
 * STM32 SPI 控制 FPGA 输出/频率 (按键控制)
 * 每按一次按键时通过 SPI 发送一个命令字节(低 4 位有效), FPGA 根据字节;
 * 主控同时维护一个频率/波形状态, 并在 LCD 实时显示。
 *   - PB5  -> 0001 (0x01) 频率加按键: 自动加频率(给 FPGA freq_up 高一级)
 *   - PB6  -> 0010 (0x02) 波形切换: 正弦波 -> 三角波 -> 方波 -> 循环, 初始为正弦波
 *   - PB7  -> 0011 (0x03) 频率减按键: 自动减频率(给 FPGA freq_dn 高一级)
 *   - PB8  -> 0101 (0x05) 固定加 1kHz
 *   - PB9  -> 0110 (0x06) 固定减 1kHz
 *   - PB10 -> 0111 (0x07) 扫频: 按下发送 0x07 开启, FPGA 从 1kHz 起每秒加 1kHz
 *   - PB11 -> 1000 (0x08) 复位: 回到正弦波 + 1kHz
 * 上电默认: 正弦波, 1kHz
 * ===================================================================== */

/* 频率边界(与 FPGA 内部 FR_x 对应, 单位 Hz) */
#define FR_1K      1000UL
#define FR_10K     10000UL
#define FR_100K    100000UL
#define FR_1M      1000000UL
#define FR_10M     10000000UL
#define FR_100M    100000000UL

/* 波形定义 */
#define WAVE_SINE   0   /* 正弦波 */
#define WAVE_TRI    1   /* 三角波 */
#define WAVE_SQUARE 2   /* 方波   */
#define WAVE_NUM    3   /* 波形数量 */

/* 扫频周期: TIM2 每 5ms 中断一次, 200 次 = 1 秒 */
#define SWEEP_PERIOD  200

static u32 g_freq = FR_1K;              /* 当前频率(Hz), 与 FPGA 同步维护 */
static u8  g_wave = WAVE_SINE;          /* 当前波形, 初始为正弦波 */
static u8  g_sweep_on = 0;              /* 扫频状态: 1=扫频中 */
static u16 g_sweep_cnt = 0;             /* 5ms 中断的次数 */
static volatile u8 g_sweep_pending = 0; /* 扫频标志到, 等主循环刷新显示 */
static u8  g_tx, g_rx;                  /* 最近一次发送/接收字节 */

static const u8 *const wave_name[WAVE_NUM] =
{
    (const u8*)"正弦波",
    (const u8*)"三角波",
    (const u8*)"方波"
};

/* 通过 SPI 发送 1 个命令字节, 同时读取 FPGA 返回 */
static void SPI_SendCmd(u8 cmd)
{
    g_tx = cmd;
    SPI_CS_L();
    g_rx = SoftSPI_ReadWriteByte(g_tx);
    SPI_CS_H();
}

/* 频率加: 给 FPGA freq_up 高一级 */
static void Freq_Up(void)
{
    if(g_freq < FR_10K)       g_freq += FR_1K;    /* <10kHz    增加 1kHz   */
    else if(g_freq < FR_100K) g_freq += FR_10K;   /* <100kHz   增加 10kHz  */
    else if(g_freq < FR_1M)   g_freq += FR_100K;  /* <1MHz     增加 100kHz */
    else if(g_freq < FR_100M) g_freq += FR_1M;    /* <100MHz   增加 1MHz   */
    else                      g_freq = FR_1K;     /* 到顶后回到起点 1kHz  */
}

/* 频率减: 给 FPGA freq_dn 高一级 */
static void Freq_Dn(void)
{
    if(g_freq > FR_10M)       g_freq -= FR_1M;    /* >10MHz    减少 1MHz   */
    else if(g_freq > FR_100K) g_freq -= FR_100K;  /* >100kHz   减少 100kHz */
    else if(g_freq > FR_10K)  g_freq -= FR_10K;   /* >10kHz    减少 10kHz  */
    else if(g_freq > FR_1K)   g_freq -= FR_1K;    /* >1kHz     减少 1kHz   */
    else                      g_freq = FR_1K;     /* 到底后保持 1kHz      */
}

/* 固定加 1kHz: 到 100MHz 回到起点 1kHz */
static void Freq_Add1K(void)
{
    if(g_freq >= FR_100M) g_freq = FR_1K;
    else                  g_freq += FR_1K;
}

/* 固定减 1kHz: 到 1kHz 后保持 1kHz */
static void Freq_Sub1K(void)
{
    if(g_freq <= FR_1K) g_freq = FR_1K;
    else                g_freq -= FR_1K;
}

/* 波形切换: 正弦波 -> 三角波 -> 方波 -> 正弦波, 循环 */
static void Wave_Switch(void)
{
    g_wave++;
    if(g_wave >= WAVE_NUM) g_wave = WAVE_SINE;
}

/* 复位: 回到正弦波 + 1kHz, 并关闭扫频 */
static void Do_Reset(void)
{
    g_wave = WAVE_SINE;
    g_freq = FR_1K;
    g_sweep_on = 0;
    g_sweep_cnt = 0;
}

/* 将 u32 转十进制字符串, 无前导位 */
static u8 U32ToStr(u32 v, u8 *buf)
{
    u8 i = 0, j;
    u8 tmp[10];
    if(v == 0) { buf[0] = '0'; buf[1] = 0; return 1; }
    while(v > 0 && i < 10) { tmp[i++] = (u8)('0' + v % 10); v /= 10; }
    for(j = 0; j < i; j++) buf[j] = tmp[i - 1 - j];
    buf[i] = 0;
    return i;
}

/* 显示一个字节的低 4 位为二进制(如 0001) */
static void LCD_ShowNibble(u16 x, u16 y, u8 v, u16 fc, u16 bc)
{
    u8 i;
    u8 s[5];
    for(i = 0; i < 4; i++) s[i] = (v & (0x08 >> i)) ? '1' : '0';
    s[4] = 0;
    LCD_ShowString(x, y, (const u8*)s, fc, bc, 16, 0);
}

/* 刷新 LCD: 波形 + 频率 + 扫频 + 通信 + 发送数据 */
static void LCD_Refresh(void)
{
    u8 buf[11];
    u8 len;

    /* 第1行: 波形 */
    LCD_Fill(0, 8, LCD_W, 28, WHITE);
    LCD_ShowChinese(0, 10, (u8*)"波形", BLACK, WHITE, 16, 0);
    LCD_ShowChar(34, 10, ':', BLACK, WHITE, 16, 0);
    LCD_ShowChinese(42, 10, (u8*)wave_name[g_wave], BLACK, WHITE, 16, 0);

    /* 第2行: 频率(单位 Hz) */
    LCD_Fill(0, 38, LCD_W, 58, WHITE);
    LCD_ShowChinese(0, 40, (u8*)"频率", BLACK, WHITE, 16, 0);
    LCD_ShowChar(34, 40, ':', BLACK, WHITE, 16, 0);
    len = U32ToStr(g_freq, buf);
    LCD_ShowString(40, 40, buf, BLACK, WHITE, 16, 0);
    LCD_ShowString(40 + (u16)len * 8, 40, (const u8*)"Hz", BLACK, WHITE, 16, 0);

    /* 第3行: 扫频状态 */
    LCD_Fill(0, 68, LCD_W, 88, WHITE);
    LCD_ShowString(0, 70, (const u8*)"SWEEP:", BLACK, WHITE, 16, 0);
    LCD_ShowString(48, 70, (const u8*)(g_sweep_on ? "ON" : "OFF"), BLACK, WHITE, 16, 0);

    /* 第4行: 通信状态 */
    LCD_Fill(0, 98, LCD_W, 118, WHITE);
    LCD_ShowChinese(0, 100, (u8*)"通信", BLACK, WHITE, 16, 0);
    LCD_ShowChar(34, 100, ':', BLACK, WHITE, 16, 0);
    if(g_rx == g_tx)
        LCD_ShowChinese(42, 100, (u8*)"成功", GREEN, WHITE, 16, 0);
    else
        LCD_ShowChinese(42, 100, (u8*)"失败", RED, WHITE, 16, 0);

    /* 第5行: 每次按下发送的数据(低4位) */
    LCD_Fill(0, 128, LCD_W, 148, WHITE);
    LCD_ShowChinese(0, 130, (u8*)"发送", BLACK, WHITE, 16, 0);
    LCD_ShowChar(34, 130, ':', BLACK, WHITE, 16, 0);
    LCD_ShowNibble(44, 130, g_tx, BLACK, WHITE);
}

/* 定时器2中断: 5ms 按键扫描 + 扫频计时 */
void TIM2_IRQHandler(void)
{
    if(TIM_GetITStatus(TIM2, TIM_IT_Update) != RESET)
    {
        TIM_ClearITPendingBit(TIM2, TIM_IT_Update);
        KEY_Scan();

        if(g_sweep_on)              /* 扫频中: 每 1 秒产生一个标志 */
        {
            if(++g_sweep_cnt >= SWEEP_PERIOD)
            {
                g_sweep_cnt = 0;
                g_sweep_pending = 1;
            }
        }
    }
}

int main(void)
{
    u8 f;

    SystemInit();          /* 系统时钟 72MHz */
    delay_init(72);
    LCD_Init();
    SoftSPI_Init();
    KEY_Init();
    KEY_Timer_Init();

    LCD_Fill(0, 0, LCD_W, LCD_H, WHITE);

    Do_Reset();            /* 上电默认: 正弦波 + 1kHz */
    SPI_SendCmd(0x08);     /* 上电先发一次复位指令, 使 FPGA 先显示一次 */
    LCD_Refresh();

    while(1)
    {
        f = KEY_GetPress();      /* 获取按键事件(位标志) */
        if(f)
        {
            if(f & KEY_FREQ_UP)    { Freq_Up();     SPI_SendCmd(0x01); g_sweep_on = 0; }
            if(f & KEY_WAVE_SW)    { Wave_Switch(); SPI_SendCmd(0x02); }
            if(f & KEY_FREQ_DOWN)  { Freq_Dn();     SPI_SendCmd(0x03); g_sweep_on = 0; }
            if(f & KEY_FSTEP_UP1)  { Freq_Add1K();  SPI_SendCmd(0x05); g_sweep_on = 0; }
            if(f & KEY_FSTEP_DN)   { Freq_Sub1K();  SPI_SendCmd(0x06); g_sweep_on = 0; }
            if(f & KEY_SWEEP)      { g_freq = FR_1K; g_sweep_on = 1; g_sweep_cnt = 0; SPI_SendCmd(0x07); }
            if(f & KEY_RESET)      { Do_Reset();    SPI_SendCmd(0x08); }

            LCD_Refresh();
        }

        if(g_sweep_pending)        /* 扫频标志到: 频率加 1kHz, 与 FPGA 自动扫频同步 */
        {
            g_sweep_pending = 0;
            Freq_Add1K();
            LCD_Refresh();
        }
    }
}
