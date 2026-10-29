#ifndef __MYSPI_H
#define __MYSPI_H


//Òý½Å¶¨Òå
#define SPI_SCK_PIN    GPIO_Pin_8
#define SPI_SCK_PORT   GPIOA
#define SPI_MOSI_PIN   GPIO_Pin_9
#define SPI_MOSI_PORT  GPIOA
#define SPI_MISO_PIN   GPIO_Pin_10
#define SPI_MISO_PORT  GPIOA
#define SPI_CS_PIN     GPIO_Pin_11
#define SPI_CS_PORT    GPIOA

#define SPI_SCK_L()    GPIO_ResetBits(SPI_SCK_PORT, SPI_SCK_PIN)
#define SPI_SCK_H()    GPIO_SetBits(SPI_SCK_PORT, SPI_SCK_PIN)
#define SPI_MOSI_L()   GPIO_ResetBits(SPI_MOSI_PORT, SPI_MOSI_PIN)
#define SPI_MOSI_H()   GPIO_SetBits(SPI_MOSI_PORT, SPI_MOSI_PIN)
#define SPI_CS_L()     GPIO_ResetBits(SPI_CS_PORT, SPI_CS_PIN)
#define SPI_CS_H()     GPIO_SetBits(SPI_CS_PORT, SPI_CS_PIN)
#define SPI_MISO_RD()  GPIO_ReadInputDataBit(SPI_MISO_PORT,SPI_MISO_PIN)

void SoftSPI_Init(void);
u8 SoftSPI_ReadWriteByte(u8 TxData);

#endif
