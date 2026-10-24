module DAC904_TOP(
	//---- 板载 200MHz 差分时钟 (AX7A035B: SYS_CLK_P=R4 / SYS_CLK_N=T4) ----
	//     内部 4 分频得到 50MHz, 再送给 PLL_CLK 产生 165MHz
	input  wire 			 sys_clk_p	,	//200MHz 差分时钟 P
	input  wire 			 sys_clk_n	,	//200MHz 差分时钟 N
	input	 wire 			 SYS_RST	,	//复位, 低有效
	//---- SPI 从机接口 (与 STM32 相连, 代替原来的 4 个按键) ----
	input  wire				 SCK		,	//STM32 PA8  (SCK)
	input  wire				 MOSI		,	//STM32 PA9  (MOSI)
	input  wire				 NSS		,	//STM32 PA11 (片选, 低有效)
	output wire				 MISO		,	//STM32 PA10 (MISO, 位回环)
	//---- 板载 LED: 指示当前波形与频率计使能 ----
	output wire	[3:0]	 led		,	//[0]正弦 [1]三角 [2]方波 [3]频率计使能
	output wire				 PD	   ,
	output wire				 DAC_CLK	,
	output wire           BEEP_EN ,
	input  wire           comparator_out,
	output wire	[13:0]    DAC_DATA,
	output wire           LED 
	
);

//DAC904的输出电压转换公式：(16383 - DAC_DATA) * （6V/16383），此公式默认不使用输出放大缩小，短路帽接12

wire	CLK_165M;

wire 	[1 :0] sel			;
wire 	[31:0] fre_k		;
wire 	[11:0] addr			;
wire 	[13:0] wave_z		;
wire 	[13:0] wave_s		;
wire 	[13:0] wave_f		;
wire	[13:0] DATA_BUF	;
wire  [63:0] freq_prod  ;
wire  [31:0] freq_hz    ;      // 实际频率，单位Hz

//---- 时钟: 200MHz 差分 -> 单端 -> 4 分频 -> 50MHz ----
wire			SYS_CLK	 ;		//50MHz, 由 200MHz 分频得到 (原名是顶层 50MHz 输入)
wire			clk_200_ibuf;	//IBUFDS 出来的单端 200MHz
wire			clk_200	 ;		//BUFG 之后的 200MHz
wire			clk_50_raw ;	//分频出来的 50MHz (还没上 BUFG)
reg	[1:0]	clk_div = 2'b00;	//2 位计数器, 最高位正好是 200/4=50MHz, 占空比 50%

// 频率计实例化
wire [31:0] measured_freq;   // 测量结果

wire meas_en;                 // 频率计使能 (由 SPI 命令控制)
wire phase_rst;               // 软复位脉冲 (由 SPI 命令控制)
wire rst_add_n;               // add_32bit 复位 = SYS_RST 与 phase_rst 合并
wire [7:0] spi_data;          // SPI 收到的字节
wire spi_valid;               // SPI 一帧接收完成脉冲

// 方波数据
assign wave_f = addr[11] ? 14'b11_1111_1111_1111 : 14'b00_0000_0000_0000;
assign BEEP_EN = 1'b0;
assign PD = 1'b0;
assign DAC_CLK  = CLK_165M;
assign DAC_DATA = DATA_BUF; // 交流输出
assign LED = (measured_freq > 32'd1_000_000) ? 1'b0 : 1'b1;
// 软复位时把相位累加器一起清零 (add_32bit 的 rst 是低有效)
assign rst_add_n = SYS_RST & ~phase_rst;
// LED 指示: 一热码显示当前波形, 第 4 个灯表示频率计使能
// 注意 AX7A035B 上 LED1~LED4 (L13/M13/K14/K13) 是"低电平点亮", 所以这里取反
assign led = ~{ meas_en, (sel == 2'b10), (sel == 2'b01), (sel == 2'b00) };
//assign freq_prod = fre_k * 32'd165_000_000;
//assign freq_hz   = freq_prod[63:32];
//assign DAC_DATA = 14'd10000; // 直流测试，0.66V左右




//200MHz 差分时钟 -> 单端 -> 4 分频得到 50MHz
IBUFDS u_sys_clk_ibufds(
	.O		(clk_200_ibuf	),
	.I		(sys_clk_p		),
	.IB		(sys_clk_n		)
);

BUFG u_sys_clk_bufg(
	.I		(clk_200_ibuf	),
	.O		(clk_200			)
);

always @(posedge clk_200)
	begin
		clk_div <= clk_div + 1'b1;
	end

assign clk_50_raw = clk_div[1];		//200MHz / 4 = 50MHz

BUFG u_clk50_bufg(
	.I		(clk_50_raw		),
	.O		(SYS_CLK			)
);

//锁相环模块 (50MHz -> 165MHz, 与原来完全一致)
PLL_CLK u_PLL_CLK(
	 .areset (!SYS_RST), 
	 .inclk0	(SYS_CLK	),
	 .c0			(CLK_165M	)
);

// 正弦波数据，ROM表
ROM_Sin u_ROM_Sin(
	.address(addr			),
	.clock	(CLK_165M	),
	.q			(wave_z		)
);

// 三角波数据，ROM表
ROM_Tri ROM_Tri(
	.address(addr			),
	.clock	(CLK_165M	),
	.q			(wave_s		)
);

//地址累加器
add_32bit u_add_32bit(
	.clk	(CLK_165M	),
	.rst	(rst_add_n	),
	.fr_k (fre_k		),
	.adder(addr			)
);

//SPI 从机: 收 STM32 发来的命令字节, 并把同一位回环给 MISO (握手用)
spi u_spi(
	.clk			(CLK_165M	),
	.rst_n		(SYS_RST	),
	.SCK			(SCK			),
	.MOSI			(MOSI			),
	.NSS			(NSS			),
	.MISO			(MISO			),
	.data_out	(spi_data	),
	.data_valid	(spi_valid	)
);

//命令解码模块 (代替原来的按键控制)
cmd_con u_cmd_con(
	.clk			(CLK_165M	),
	.rst_n		(SYS_RST	),
	.cmd			(spi_data	),
	.cmd_valid	(spi_valid	),
	.sel_wave	(sel			),
	.fre_k		(fre_k		),
	.meas_en		(meas_en		),
	.phase_rst	(phase_rst	)
);

//波形输出选择模块
sel_wave u_sel_wave(
	.clk		(CLK_165M	),
	.rst_n	(SYS_RST	),
	.sel		(sel			),
	.da_ina (wave_z		),
	.da_inb (wave_s		),
	.da_inc (wave_f		),
	.da_out (DATA_BUF	)
);

simple_freq_meter u_simple_freq_meter(
    .clk       (CLK_165M),
    .rst_n     (SYS_RST),
    .freq_in   (comparator_out),
    .meas_en   (meas_en),          // 连接使能
    .frequency (measured_freq)
);

endmodule
