//============================================================================
//  Module : cmd_con  --  SPI 命令解码器 (代替原来的 key_con + key_delay)
//
//  时钟域 : CLK_165M (与 spi 从机同域, 不需要任何跨时钟域握手)
//
//  指令表 (STM32 通过 SPI 发来的字节, LCD 上显示成 4 位字符串):
//     0001 (8'h01)  频率 +1 档   (自适应步进, 与原 key1 逐条一致)
//     0010 (8'h02)  换波形: 正弦 -> 三角 -> 方波 -> 正弦 (同原 key2)
//     0011 (8'h03)  频率 -1 档   (同原 key3)
//     0100 (8'h04)  频率计使能 开/关 (同原 key4, 上电默认开)
//     0101 (8'h05)  频率 +1kHz 固定细调  (新增定义)
//     0110 (8'h06)  频率 -1kHz 固定细调  (新增定义)
//     1000 (8'h08)  软复位: 频率回 1kHz, 波形回正弦, 使能开, 相位累加器清零
//     其它          忽略, 保持当前状态
//
//  频率字 fre_k 的含义: 165MHz 下每周期累加 fre_k, 取累加器高 12 位做 ROM 地址,
//  所以 输出频率 = fre_k * 165e6 / 2^32。fre_k = 26031 即 1kHz, 2603100000 即 100MHz。
//
//  档位步进(逐条照搬原 key_con.v):
//     加: <10kHz 加 1kHz; <100kHz 加 10kHz; <1MHz 加 100kHz; <100MHz 加 1MHz;
//         否则回卷到 1kHz
//     减: >10MHz 减 1MHz; >100kHz 减 100kHz; >10kHz 减 10kHz; >1kHz 减 1kHz;
//         否则保持 1kHz
//============================================================================
module cmd_con(
	input  wire			clk		,	//165MHz
	input  wire			rst_n	,	//复位, 低有效
	input  wire	[7:0]	cmd		,	//本帧收到的命令字节
	input  wire			cmd_valid,	//命令有效脉冲 (1 个 clk 宽)
	output reg	[1:0]	sel_wave,	//波形选择: 00 正弦 / 01 三角 / 10 方波
	output reg	[31:0]	fre_k	,	//频率字
	output reg			meas_en	,	//频率计使能
	output reg			phase_rst	//相位累加器复位脉冲 (软复位时 1 个 clk 宽)
	);

//频率字常量 ---------------------------------------------------------------
localparam [31:0] FR_1K   = 32'd26031		;	//1kHz
localparam [31:0] FR_10K  = 32'd260310		;	//10kHz   (阈值)
localparam [31:0] FR_100K = 32'd2603100		;	//100kHz  (阈值)
localparam [31:0] FR_1M   = 32'd26031000	;	//1MHz    (阈值)
localparam [31:0] FR_10M  = 32'd260310000	;	//10MHz   (阈值)
localparam [31:0] FR_100M = 32'd2603100000	;	//100MHz  (上限)

//频率加一档 (与原 key_con 中 key1 分支一致)
function [31:0] freq_up;
	input [31:0] f;
	begin
		if		(f < FR_10K)	freq_up = f + FR_1K	;	//<10kHz   步进 1kHz
		else if	(f < FR_100K)	freq_up = f + FR_10K;	//<100kHz  步进 10kHz
		else if	(f < FR_1M)		freq_up = f + FR_100K;	//<1MHz    步进 100kHz
		else if	(f < FR_100M)	freq_up = f + FR_1M	;	//<100MHz  步进 1MHz
		else					freq_up = FR_1K		;	//到顶后回卷到 1kHz
	end
endfunction

//频率减一档 (与原 key_con 中 key3 分支一致)
function [31:0] freq_dn;
	input [31:0] f;
	begin
		if		(f > FR_10M)	freq_dn = f - FR_1M	;	//>10MHz   步进 1MHz
		else if	(f > FR_100K)	freq_dn = f - FR_100K;	//>100kHz  步进 100kHz
		else if	(f > FR_10K)	freq_dn = f - FR_10K;	//>10kHz   步进 10kHz
		else if	(f > FR_1K)		freq_dn = f - FR_1K	;	//>1kHz    步进 1kHz
		else					freq_dn = FR_1K		;	//到底后保持 1kHz
	end
endfunction

//命令解码 ----------------------------------------------------------------
always @(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
			begin
				sel_wave  <= 2'b00		;	//正弦
				fre_k     <= FR_1K		;	//1kHz
				meas_en   <= 1'b1		;	//频率计默认开启
				phase_rst <= 1'b0		;
			end
		else
			begin
				phase_rst <= 1'b0;			//默认只打一拍
				if(cmd_valid)
					begin
						case(cmd)
							8'h01: fre_k     <= freq_up(fre_k)				;	//0001 频率+1档
							8'h03: fre_k     <= freq_dn(fre_k)				;	//0011 频率-1档
							8'h05: fre_k     <= (fre_k + FR_1K > FR_100M) ? FR_1K
							                                              : fre_k + FR_1K;	//0101 +1kHz
							8'h06: fre_k     <= (fre_k > FR_1K) ? fre_k - FR_1K
							                                    : FR_1K		;	//0110 -1kHz
							8'h02: sel_wave  <= (sel_wave == 2'b10) ? 2'b00
							                                        : sel_wave + 2'b01;	//0010 换波形
							8'h04: meas_en   <= ~meas_en						;	//0100 使能开关
							8'h08: begin										//1000 软复位
								       sel_wave  <= 2'b00;
								       fre_k     <= FR_1K;
								       meas_en   <= 1'b1;
								       phase_rst <= 1'b1;
							       end
							default: ;											//其它码忽略
						endcase
					end
			end
	end

endmodule
