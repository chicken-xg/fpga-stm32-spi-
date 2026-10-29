//============================================================================
//  Module : tb_spi_cmd  --  SPI 从机 + 命令解码 + 扫频控制仿真
//
//  覆盖内容:
//    1) MISO 片选空闲为低, 多数据/多 SCK 时序位回环
//    2) 原有 SPI 命令、非法命令和软复位
//    3) KEY4 短按不触发、有效按下切换扫频
//    4) 1kHz 固定步进、停止保持、再次启动从 1kHz 开始
//    5) 手动频率命令停止扫频, 100MHz 到 1kHz 的完整回卷
//
//  为缩短仿真时间, 主实例把 20ms/1s 定时参数缩成 16/256 个时钟;
//  回卷实例进一步缩成 1/1。顶层默认参数仍对应实际硬件。
//============================================================================
`timescale 1ns / 1ps

module tb_spi_cmd;

	localparam [31:0] FR_1K   = 32'd26031;
	localparam [31:0] FR_100M = 32'd2603100000;
	localparam integer TEST_DEBOUNCE = 16;
	localparam integer TEST_STEP     = 256;

	//165MHz 系统时钟
	reg clk = 1'b0;
	always #3.0303 clk = ~clk;

	//STM32 软件 SPI 信号
	reg			rst_n = 1'b0;
	reg			SCK   = 1'b0;
	reg			MOSI  = 1'b0;
	reg			NSS   = 1'b1;
	reg			KEY4  = 1'b1;
	wire		MISO;

	wire [7:0]	cmd;
	wire		cmd_valid;
	wire [1:0]	sel_wave;
	wire [31:0]	fre_k;
	wire		meas_en;
	wire		phase_rst;

	spi u_spi(
		.clk		(clk),
		.rst_n		(rst_n),
		.SCK		(SCK),
		.MOSI		(MOSI),
		.NSS		(NSS),
		.MISO		(MISO),
		.data_out	(cmd),
		.data_valid	(cmd_valid)
	);

	cmd_con #(
		.KEY_DEBOUNCE_CYCLES(TEST_DEBOUNCE),
		.SWEEP_STEP_CYCLES  (TEST_STEP)
	) u_cmd_con(
		.clk		(clk),
		.rst_n		(rst_n),
		.cmd		(cmd),
		.cmd_valid	(cmd_valid),
		.KEY4		(KEY4),
		.sel_wave	(sel_wave),
		.fre_k		(fre_k),
		.meas_en	(meas_en),
		.phase_rst	(phase_rst)
	);

	//独立的快速回卷实例, 每拍增加一次 1kHz
	reg			wrap_key = 1'b1;
	wire [31:0]	wrap_fre;
	reg [31:0]	wrap_prev = 32'd0;
	reg			wrap_seen = 1'b0;
	reg [31:0]	wrap_value = 32'd0;
	reg			wrap_step_bad = 1'b0;

	cmd_con #(
		.KEY_DEBOUNCE_CYCLES(1),
		.SWEEP_STEP_CYCLES  (1)
	) u_wrap_cmd_con(
		.clk		(clk),
		.rst_n		(rst_n),
		.cmd		(8'h00),
		.cmd_valid	(1'b0),
		.KEY4		(wrap_key),
		.sel_wave	(),
		.fre_k		(wrap_fre),
		.meas_en	(),
		.phase_rst	()
	);

	always @(posedge clk)
		begin
			if(wrap_fre > wrap_prev)
				begin
					if((wrap_fre - wrap_prev) != FR_1K)
						wrap_step_bad <= 1'b1;
				end
			else if(wrap_fre < wrap_prev)
				begin
					if(wrap_fre == FR_1K)
						begin
							wrap_seen <= 1'b1;
							wrap_value <= wrap_fre;
						end
					else
						wrap_step_bad <= 1'b1;
				end
			wrap_prev <= wrap_fre;
		end

	reg			prst_seen = 1'b0;
	always @(posedge clk)
		if(phase_rst)
			prst_seen <= 1'b1;

	integer errors = 0;
	integer xfers = 0;
	integer xfers_ok = 0;
	reg [7:0] rx;
	reg [31:0] f_before;
	integer k;
	integer h;
	integer timeout;
	integer holds [0:3];

	task stm32_xfer;
		input [7:0] tx;
		input integer t_hold;
		output [7:0] rxo;
		integer i;
		reg [7:0] t;
		reg [7:0] r;
		begin
			t = tx;
			r = 8'h00;
			NSS = 1'b0;
			#200;

			for(i = 0; i < 8; i = i + 1)
				begin
					MOSI = t[7];
					t = {t[6:0], 1'b0};
					#200;
					SCK = 1'b1;
					#(t_hold);
					r = {r[6:0], MISO};
					SCK = 1'b0;
					#200;
				end

			NSS = 1'b1;
			#500;
			rxo = r;
		end
	endtask

	task chk;
		input [7:0] c;
		input [31:0] ef;
		input [1:0] es;
		input ee;
		begin
			if((fre_k !== ef) || (sel_wave !== es) || (meas_en !== ee))
				begin
					errors = errors + 1;
					$display("  [FAIL] cmd=%08b fre_k=%0d(exp %0d) sel=%b(exp %b) meas=%b(exp %b)",
					         c, fre_k, ef, sel_wave, es, meas_en, ee);
				end
			else
				$display("  [ OK ] cmd=%08b fre_k=%0d sel=%b meas=%b",
				         c, fre_k, sel_wave, meas_en);
		end
	endtask

	task key4_press;
		begin
			KEY4 = 1'b0;
			repeat(TEST_DEBOUNCE + 4) @(posedge clk);
			KEY4 = 1'b1;
			repeat(TEST_DEBOUNCE + 4) @(posedge clk);
		end
	endtask

	initial
		begin
			holds[0] = 0;
			holds[1] = 100;
			holds[2] = 300;
			holds[3] = 1000;

			$display("");
			$display("==== SPI + 命令 + 扫频单元仿真 ====");
			#200 rst_n = 1'b1;
			#200;

			$display("-- 1. 复位默认值和 MISO 空闲电平 --");
			chk(8'h00, FR_1K, 2'b00, 1'b1);
			if(MISO !== 1'b0)
				begin
					errors = errors + 1;
					$display("  [FAIL] NSS 空闲时 MISO=%b, 应为 0", MISO);
				end
			else
				$display("  [ OK ] NSS 空闲时 MISO=0");

			$display("-- 2. 多种数据和 SCK 时序的位回环 --");
			for(h = 0; h < 4; h = h + 1)
				begin
					for(k = 0; k < 16; k = k + 1)
						begin
							stm32_xfer(k[7:0], holds[h], rx);
							xfers = xfers + 1;
							if(rx !== k[7:0])
								begin
									errors = errors + 1;
									$display("  [FAIL] SCK_hold=%0dns tx=%08b rx=%08b", holds[h], k[7:0], rx);
								end
							else
								xfers_ok = xfers_ok + 1;
						end
					stm32_xfer(8'hFF, holds[h], rx);
					xfers = xfers + 1;
					if(rx !== 8'hFF)
						begin
							errors = errors + 1;
							$display("  [FAIL] SCK_hold=%0dns tx=11111111 rx=%08b", holds[h], rx);
						end
					else
						xfers_ok = xfers_ok + 1;
				end
			$display("  -> 位回环 %0d/%0d", xfers_ok, xfers);
			if(NSS)
				#100;
			if(MISO !== 1'b0)
				begin
					errors = errors + 1;
					$display("  [FAIL] 帧结束后 MISO 未回到 0");
				end

			$display("-- 3. 软复位和短按滤除 --");
			stm32_xfer(8'h08, 300, rx);
			chk(8'h08, FR_1K, 2'b00, 1'b1);
			if(!prst_seen)
				begin
					errors = errors + 1;
					$display("  [FAIL] 软复位 phase_rst 未出现");
				end
			else
				$display("  [ OK ] 软复位 phase_rst 已出现");

			KEY4 = 1'b0;
			repeat(TEST_DEBOUNCE / 2) @(posedge clk);
			KEY4 = 1'b1;
			repeat(TEST_DEBOUNCE + 4) @(posedge clk);
			repeat(TEST_STEP + 8) @(posedge clk);
			chk(8'h08, FR_1K, 2'b00, 1'b1);

			$display("-- 4. KEY4 启动、1kHz 步进和停止保持 --");
			key4_press();
			chk(8'h08, FR_1K, 2'b00, 1'b1);
			repeat(TEST_STEP + 4) @(posedge clk);
			if(fre_k !== (FR_1K * 2))
				begin
					errors = errors + 1;
					$display("  [FAIL] 第一步 fre_k=%0d, 期望 %0d", fre_k, FR_1K * 2);
				end
			else
				$display("  [ OK ] 第一步 fre_k=%0d", fre_k);
			repeat(TEST_STEP) @(posedge clk);
			if(fre_k !== (FR_1K * 3))
				begin
					errors = errors + 1;
					$display("  [FAIL] 第二步 fre_k=%0d, 期望 %0d", fre_k, FR_1K * 3);
				end
			else
				$display("  [ OK ] 第二步 fre_k=%0d", fre_k);

			key4_press();
			f_before = fre_k;
			repeat(TEST_STEP * 2) @(posedge clk);
			if(fre_k !== f_before)
				begin
					errors = errors + 1;
					$display("  [FAIL] 停止后频率仍变化: %0d -> %0d", f_before, fre_k);
				end
			else
				$display("  [ OK ] 停止后保持 fre_k=%0d", fre_k);

			key4_press();
			if(fre_k !== FR_1K)
				begin
					errors = errors + 1;
					$display("  [FAIL] 再次启动未回到 1kHz: fre_k=%0d", fre_k);
				end
			else
				$display("  [ OK ] 再次启动回到 1kHz");

			$display("-- 5. 波形/频率计命令不打断扫频, 频率命令停止扫频 --");
			f_before = fre_k;
			stm32_xfer(8'h02, 300, rx);
			repeat(TEST_STEP + 8) @(posedge clk);
			if((fre_k <= f_before) || (sel_wave !== 2'b01))
				begin
					errors = errors + 1;
					$display("  [FAIL] 0010 后扫频/波形异常 fre=%0d sel=%b", fre_k, sel_wave);
				end
			else
				$display("  [ OK ] 0010 换三角波后扫频继续 fre=%0d", fre_k);

			f_before = fre_k;
			stm32_xfer(8'h04, 300, rx);
			repeat(TEST_STEP + 8) @(posedge clk);
			if((fre_k <= f_before) || meas_en)
				begin
					errors = errors + 1;
					$display("  [FAIL] 0100 后扫频/使能异常 fre=%0d meas=%b", fre_k, meas_en);
				end
			else
				$display("  [ OK ] 0100 关闭频率计后扫频继续 fre=%0d", fre_k);

			stm32_xfer(8'h05, 300, rx);
			f_before = fre_k;
			repeat(TEST_STEP * 2) @(posedge clk);
			if(fre_k !== f_before)
				begin
					errors = errors + 1;
					$display("  [FAIL] 0101 后扫频未停止 %0d -> %0d", f_before, fre_k);
				end
			else
				$display("  [ OK ] 0101 固定 +1kHz 后停止扫频, fre_k=%0d", fre_k);

			$display("-- 6. 原有命令和非法码 --");
			stm32_xfer(8'h08, 300, rx);
			stm32_xfer(8'h01, 300, rx); chk(8'h01, FR_1K * 2, 2'b00, 1'b1);
			stm32_xfer(8'h03, 300, rx); chk(8'h03, FR_1K, 2'b00, 1'b1);
			stm32_xfer(8'h02, 300, rx); chk(8'h02, FR_1K, 2'b01, 1'b1);
			stm32_xfer(8'h02, 300, rx); chk(8'h02, FR_1K, 2'b10, 1'b1);
			stm32_xfer(8'h02, 300, rx); chk(8'h02, FR_1K, 2'b00, 1'b1);
			stm32_xfer(8'h04, 300, rx); chk(8'h04, FR_1K, 2'b00, 1'b0);
			stm32_xfer(8'h04, 300, rx); chk(8'h04, FR_1K, 2'b00, 1'b1);
			stm32_xfer(8'h06, 300, rx); chk(8'h06, FR_1K, 2'b00, 1'b1);
			stm32_xfer(8'h0F, 300, rx); chk(8'h0F, FR_1K, 2'b00, 1'b1);

			$display("-- 7. 1kHz 到 100MHz 的完整回卷 --");
			wrap_key = 1'b0;
			repeat(4) @(posedge clk);
			wrap_key = 1'b1;
			timeout = 0;
			while((!wrap_seen) && (timeout < 200000))
				begin
					@(posedge clk);
					timeout = timeout + 1;
				end
			if(!wrap_seen || (wrap_value !== FR_1K) || wrap_step_bad)
				begin
					errors = errors + 1;
					$display("  [FAIL] 回卷异常 seen=%b value=%0d step_bad=%b", wrap_seen, wrap_value, wrap_step_bad);
				end
			else
				$display("  [ OK ] 100MHz 后回到 fre_k=%0d, 使用 %0d 个时钟", wrap_value, timeout);

			$display("");
			$display("==== 结果: 位回环 %0d/%0d, 失败项 %0d ====", xfers_ok, xfers, errors);
			if((errors == 0) && (xfers_ok == xfers))
				$display("PASS: 全部通过");
			else
				$display("FAIL: 存在错误");
			$finish;
		end

endmodule
