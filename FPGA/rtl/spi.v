//============================================================================
//  Module : spi  --  SPI 从机 (STM32 软件 SPI 主机的对端)
//
//  来源 : SPI_FPGA/FPGA_xc7a35t_spi/cs11/cs11.srcs/sources_1/new/spi.v
//         (该版本已在 cs11 工程里仿真 + 综合 + 实现验证过)
//         本次合并到波形发生器工程, 逻辑一字未改, 只把时钟域从 200MHz
//         改成 PLL 出来的 165MHz (clk 由顶层接 CLK_165M)。
//
//  协议 (与 STM32 端 MYSPI.c 的 SoftSPI_ReadWriteByte 完全对应):
//     Mode0 (CPOL=0, CPHA=0), MSB 先发, 8bit
//     NSS 低有效; 每帧: NSS 拉低 -> 8 个 SCK -> NSS 拉高
//
//  STM32 主机每个 bit 的动作是:
//     1) 在 SCK 为低时把这一位写到 MOSI
//     2) 拉高 SCK
//     3) 在 SCK 仍为高时读 MISO
//     4) 拉低 SCK
//
//  【握手关键】STM32 的判据是 g_rx == g_tx (期望原样回环)。
//  片选有效时 MISO 直接输出同步后的 MOSI, 因此在 SCK 上升沿之前就已经稳定,
//  主机采样得到的就是当前发送位 -> 8 位下来 RxData 与 TxData 完全相同。
//  这样不依赖主机拉高 SCK 后具体延时多久, 降低了高速 SCK 下的采样竞争风险。
//
//  一帧收完后: data_out 给出收到的字节, data_valid 打一个 clk 的脉冲,
//  交给 cmd_con 做命令解码 (代替原来的 4 个按键)。
//============================================================================
module spi(
	input	wire		clk,		//系统时钟 (本工程为 165MHz)
	input	wire		rst_n,		//复位, 低有效
	input	wire		SCK,		//SPI 时钟 (STM32 的 PA8)
	input	wire		MOSI,		//主机输出从机输入 (STM32 的 PA9)
	input	wire		NSS,		//片选, 低有效 (STM32 的 PA11/CS)
	output	wire		MISO,		//从机输出主机输入 (STM32 的 PA10)
	output	reg	[7:0]	data_out,	//本帧接收到的字节
	output	reg			data_valid	//一帧接收完成脉冲, 1 个 clk 宽
	);

//同步信号
//----------------------------------------------------------------------------------------
// SCK / NSS / MOSI 都用 3 位移位寄存器同步到 clk 域。
// 三者级数相同, 这样它们之间不会多出额外的相对延迟。
reg [2:0] SCKr;
reg [2:0] NSSr;
reg [2:0] MOSIr;

always @(posedge clk)
	begin
		SCKr  <= {SCKr[1:0],  SCK};
		NSSr  <= {NSSr[1:0],  NSS};
		MOSIr <= {MOSIr[1:0], MOSI};
	end

wire SCK_rising  = (SCKr[2:1] == 2'b01);	//SCK 上升沿: Mode0 的采样点
wire SCK_falling = (SCKr[2:1] == 2'b10);	//SCK 下降沿

wire NSS_active  = ~NSSr[1];				//片选有效 (低电平)
wire NSS_start   = (NSSr[2:1] == 2'b10);	//NSS 下降沿: 一帧开始
wire NSS_end     = (NSSr[2:1] == 2'b01);	//NSS 上升沿: 一帧结束

wire MOSI_data   = MOSIr[2];				//与 SCK/NSS 同深度的 MOSI
//----------------------------------------------------------------------------------------

//接收部分
//----------------------------------------------------------------------------------------
reg [7:0] rx_shift;	//接收移位寄存器, 高位在前

always @(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
			begin
				rx_shift <= 8'd0;
			end
		else if(!NSS_active)
			begin
				//片选无效(帧与帧之间): 清空接收寄存器
				rx_shift <= 8'd0;
			end
		else if(SCK_rising)
			begin
				//Mode0: 在 SCK 上升沿采样 MOSI
				rx_shift <= {rx_shift[6:0], MOSI_data};
			end
	end

//一帧结束后把收到的字节送出去 (data_valid 打一个 clk 的脉冲)
always @(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
			begin
				data_out   <= 8'd0;
				data_valid <= 1'b0;
			end
		else
			begin
				data_valid <= 1'b0;
				if(NSS_end)
					begin
						data_out   <= rx_shift;
						data_valid <= 1'b1;
					end
			end
	end
//----------------------------------------------------------------------------------------

//发送部分 (回环)
//----------------------------------------------------------------------------------------
//MISO 在片选无效时保持低电平, 有效时稳定输出当前 MOSI 位。
assign MISO = NSS_active ? MOSI_data : 1'b0;
//----------------------------------------------------------------------------------------

endmodule
