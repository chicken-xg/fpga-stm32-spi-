//============================================================================
//  Module : tb_spi_cmd  --  spi 从机 + cmd_con 命令解码的测试平台
//
//  主机模型就是 STM32 端 MYSPI.c 里 SoftSPI_ReadWriteByte() 的逐条翻译:
//
//      NSS = 0
//      for(i=0;i<8;i++) {
//          MOSI = (tx & 0x80);  tx <<= 1;      // 1) SCK 低时写 MOSI
//          SCK  = 1;                            // 2) 拉高 SCK
//          #(SCK 高电平保持时间)                 // 3) 软件 SPI 的实际耗时
//          rx = (rx<<1) | MISO;                 // 4) 在 SCK 高时读 MISO
//          SCK  = 0;                            // 5) 拉低 SCK
//      }
//      NSS = 1
//
//  检查项:
//   1) 位回环: 4 个命令码 x 3 档 SCK 高电平时间 = 12 帧, rx 必须等于 tx
//      (这正是 STM32 main.c 里 g_rx==g_tx 的判据)
//   2) 命令解码: 0001/0010/0011/0100/0101/0110/1000 的动作与指令表一致,
//      非法码不改变状态, 1000 会打出 phase_rst 脉冲
//   3) 频率档位回卷: 连发 200 次 0001 后 fre_k 仍然合法且发生过回卷
//
//  注: 本测试平台只跑 spi + cmd_con, 不例化 PLL/ROM; 完整顶层见 tb_top_spi.v。
//============================================================================
`timescale 1ns / 1ps

module tb_spi_cmd;

	//---- 165MHz 时钟 (周期 6.0606ns) ----
	reg clk = 1'b0;
	always #3.0303 clk = ~clk;

	//---- 复位 / STM32 侧信号 ----
	reg			rst_n = 1'b0;
	reg			SCK   = 1'b0;
	reg			MOSI  = 1'b0;
	reg			NSS   = 1'b1;
	wire			MISO;

	//---- 被测设计 ----
	wire	[7:0]		cmd;
	wire				cmd_valid;
	wire	[1:0]		sel_wave;
	wire	[31:0]		fre_k;
	wire				meas_en;
	wire				phase_rst;

	spi u_spi (
		.clk			(clk),
		.rst_n		(rst_n),
		.SCK			(SCK),
		.MOSI			(MOSI),
		.NSS			(NSS),
		.MISO			(MISO),
		.data_out	(cmd),
		.data_valid	(cmd_valid)
	);

	cmd_con u_cmd_con (
		.clk			(clk),
		.rst_n		(rst_n),
		.cmd			(cmd),
		.cmd_valid	(cmd_valid),
		.sel_wave	(sel_wave),
		.fre_k		(fre_k),
		.meas_en		(meas_en),
		.phase_rst	(phase_rst)
	);

	//---- 监视器: 软复位脉冲 / 频率回卷 ----
	reg			prst_seen = 1'b0;
	reg	[31:0]	fre_prev  = 32'd0;
	reg			wrap_seen = 1'b0;

	always @(posedge clk)
		begin
			if (phase_rst) prst_seen <= 1'b1;
			if (fre_k < fre_prev) wrap_seen <= 1'b1;
			fre_prev <= fre_k;
		end

	//---- 记分板 ----
	integer		errors    = 0;
	integer		xfers     = 0;
	integer		xfers_ok  = 0;
	reg	[7:0]		rx;

	//--------------------------------------------------------------------
	// STM32 软件 SPI 主机行为模型 (SoftSPI_ReadWriteByte)
	//--------------------------------------------------------------------
	task stm32_xfer;
		input	[7:0]		tx;
		input	integer		t_hold;
		output	[7:0]		rxo;
		integer				i;
		reg		[7:0]		t;
		reg		[7:0]		r;
		begin
			t = tx;
			r = 8'h00;

			NSS = 1'b0;			//SPI_CS_L()
			#200;				//函数调用开销

			for(i = 0; i < 8; i = i + 1)
				begin
					MOSI = t[7];			//1) 先写 MOSI
					t    = {t[6:0], 1'b0};	//   TxData <<= 1
					#200;					//   MOSI 建立时间

					SCK = 1'b1;				//2) 拉高 SCK
					#(t_hold);				//3) 软件 SPI 在这里去读 MISO
					r = {r[6:0], MISO};		//4) 采样 MISO
					SCK = 1'b0;				//5) 拉低 SCK
					#200;					//   下一位 MOSI 之前的间隔
				end

			NSS = 1'b1;			//SPI_CS_H()
			#500;				//帧间隔
			rxo = r;
		end
	endtask

	//--------------------------------------------------------------------
	// 状态检查: 频率字 / 波形选择 / 频率计使能
	//--------------------------------------------------------------------
	task chk;
		input	[7:0]		c;		//刚发的命令码
		input	[31:0]	ef;		//期望 fre_k
		input	[1:0]		es;		//期望 sel_wave
		input				ee;		//期望 meas_en
		begin
			if ((fre_k !== ef) || (sel_wave !== es) || (meas_en !== ee))
				begin
					errors = errors + 1;
					$display("  [FAIL] cmd=%04b : fre_k=%0d (exp %0d) sel=%b (exp %b) meas_en=%b (exp %b)", c, fre_k, ef, sel_wave, es, meas_en, ee);
				end
			else
				$display("  [ OK ] cmd=%04b : fre_k=%0d  sel=%b  meas_en=%b", c, fre_k, sel_wave, meas_en);
		end
	endtask

	//--------------------------------------------------------------------
	// 测试主体
	//--------------------------------------------------------------------
	integer		k;
	integer		h;
	integer		holds [0:2];

	initial
		begin
			holds[0] = 100;		//SCK 高电平 100ns
			holds[1] = 300;		//SCK 高电平 300ns
			holds[2] = 1000;	//SCK 高电平 1us

			$display("");
			$display("==== 仿真 A: SPI 位回环 + 命令解码 (spi + cmd_con, clk=165MHz) ====");

			#200 rst_n = 1'b1;
			#200;

			//---- 1. 复位后的默认状态 ----
			$display("-- 1. 复位默认值 (1kHz / 正弦 / 使能开) --");
			chk(8'h00, 32'd26031, 2'b00, 1'b1);

			//---- 2. 位回环: 4 码 x 3 档 SCK 高电平 ----
			$display("-- 2. 位回环 (rx 必须等于 tx) --");
			for (h = 0; h < 3; h = h + 1)
				begin
					for (k = 1; k <= 4; k = k + 1)
						begin
							stm32_xfer(k[7:0], holds[h], rx);
							xfers = xfers + 1;
							if (rx !== k[7:0])
								begin
									errors = errors + 1;
									$display("  [FAIL] SCK_hold=%0dns tx=%08b rx=%08b (STM32 会判通信失败)", holds[h], k[7:0], rx);
								end
							else
								begin
									xfers_ok = xfers_ok + 1;
									$display("  [ OK ] SCK_hold=%0dns tx=%08b rx=%08b led=%b", holds[h], k[7:0], rx, {meas_en, (sel_wave==2'b10), (sel_wave==2'b01), (sel_wave==2'b00)});
								end
						end
				end
			$display("  -> 位回环 %0d/%0d", xfers_ok, xfers);

			//---- 3. 1000 软复位 ----
			$display("-- 3. 1000 软复位 --");
			prst_seen = 1'b0;
			stm32_xfer(8'h08, 300, rx);
			chk(8'h08, 32'd26031, 2'b00, 1'b1);
			if (prst_seen !== 1'b1)
				begin
					errors = errors + 1;
					$display("  [FAIL] 1000 : phase_rst 脉冲没有出现");
				end
			else
				$display("  [ OK ] 1000 : phase_rst 脉冲已出现 (相位累加器被清零)");

			//---- 4. 命令解码 ----
			$display("-- 4. 命令解码 --");
			stm32_xfer(8'h01, 300, rx); chk(8'h01, 32'd52062, 2'b00, 1'b1);
			stm32_xfer(8'h01, 300, rx); chk(8'h01, 32'd78093, 2'b00, 1'b1);
			stm32_xfer(8'h01, 300, rx); chk(8'h01, 32'd104124, 2'b00, 1'b1);
			stm32_xfer(8'h03, 300, rx); chk(8'h03, 32'd78093, 2'b00, 1'b1);
			stm32_xfer(8'h02, 300, rx); chk(8'h02, 32'd78093, 2'b01, 1'b1);
			stm32_xfer(8'h02, 300, rx); chk(8'h02, 32'd78093, 2'b10, 1'b1);
			stm32_xfer(8'h02, 300, rx); chk(8'h02, 32'd78093, 2'b00, 1'b1);
			stm32_xfer(8'h04, 300, rx); chk(8'h04, 32'd78093, 2'b00, 1'b0);
			stm32_xfer(8'h04, 300, rx); chk(8'h04, 32'd78093, 2'b00, 1'b1);
			stm32_xfer(8'h05, 300, rx); chk(8'h05, 32'd104124, 2'b00, 1'b1);
			stm32_xfer(8'h06, 300, rx); chk(8'h06, 32'd78093, 2'b00, 1'b1);
			stm32_xfer(8'h06, 300, rx); chk(8'h06, 32'd52062, 2'b00, 1'b1);
			stm32_xfer(8'h06, 300, rx); chk(8'h06, 32'd26031, 2'b00, 1'b1);
			stm32_xfer(8'h06, 300, rx); chk(8'h06, 32'd26031, 2'b00, 1'b1);

			//---- 5. 非法码忽略 ----
			$display("-- 5. 非法码 1111 应被忽略 --");
			stm32_xfer(8'h0F, 300, rx);
			if (rx !== 8'h0F)
				begin
					errors = errors + 1;
					$display("  [FAIL] 1111 回环: rx=%08b", rx);
				end
			chk(8'h0F, 32'd26031, 2'b00, 1'b1);

			//---- 6. 频率回卷性质 ----
			$display("-- 6. 连发 200 次 0001 (检查跑到 100MHz 后回卷) --");
			wrap_seen = 1'b0;
			for (k = 0; k < 200; k = k + 1)
				stm32_xfer(8'h01, 100, rx);

			if (wrap_seen !== 1'b1)
				begin
					errors = errors + 1;
					$display("  [FAIL] 200 次加档都没有回卷");
				end
			else if ((fre_k < 32'd26031) || (fre_k > 32'd2603100000) || ((fre_k % 32'd26031) != 32'd0))
				begin
					errors = errors + 1;
					$display("  [FAIL] 回卷后 fre_k=%0d 不是合法档位", fre_k);
				end
			else
				$display("  [ OK ] 发生过回卷, 且 fre_k=%0d 仍是合法档位", fre_k);

			//---- 7. 收尾: 1000 回默认 ----
			$display("-- 7. 1000 收尾回默认 --");
			stm32_xfer(8'h08, 300, rx);
			chk(8'h08, 32'd26031, 2'b00, 1'b1);

			$display("");
			$display("==== 结果: 位回环 %0d/%0d, 失败项 %0d ====", xfers_ok, xfers, errors);
			if ((errors == 0) && (xfers_ok == xfers))
				$display("PASS: 全部通过");
			else
				$display("FAIL: 存在错误");

			$finish;
		end

endmodule
