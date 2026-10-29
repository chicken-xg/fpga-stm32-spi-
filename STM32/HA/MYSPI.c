#include "stm32f10x.h"
#include "MYSPI.h"


void SoftSPI_Init(void)
{
    GPIO_InitTypeDef GPIO_InitStructure;
    RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOA, ENABLE);

    //SCK MOSI CS 推挽输出
    GPIO_InitStructure.GPIO_Pin = SPI_SCK_PIN | SPI_MOSI_PIN | SPI_CS_PIN;
    GPIO_InitStructure.GPIO_Mode = GPIO_Mode_Out_PP;
    GPIO_InitStructure.GPIO_Speed = GPIO_Speed_50MHz;
    GPIO_Init(GPIOA, &GPIO_InitStructure);

    //MISO 浮空输入
    GPIO_InitStructure.GPIO_Pin = SPI_MISO_PIN;
    GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IN_FLOATING;
    GPIO_Init(GPIOA, &GPIO_InitStructure);

    SPI_SCK_L();  //Mode0空闲SCK低
    SPI_CS_H();   //CS默认拉高
}

//软件SPI读写1字节 Mode0 MSB先行
u8 SoftSPI_ReadWriteByte(u8 TxData)
{
    u8 i;
    u8 RxData = 0;
    for(i=0;i<8;i++)
    {
        if(TxData & 0x80)
            SPI_MOSI_H();
        else
            SPI_MOSI_L();
        TxData <<= 1;

        SPI_SCK_H();
        RxData <<=1;
        if(SPI_MISO_RD())
            RxData |= 0x01;
        SPI_SCK_L();
    }
    return RxData;
}
