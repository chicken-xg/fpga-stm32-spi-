//============================================================================
//  Module : tb_top_spi  --  完整顶层 DAC904_TOP 的集成仿真
//
//  验证合并后"SPI 命令 -> 波形/频率"的整条链路真的接到了原来的波形发生器上:
//    1) PLL 锁定, DAC_CLK 正常翻转
//    2) 默认 1kHz 正弦: 用 DAC_DATA[13] 的周期测输出频率, 用相邻样本最大增量
//       (正弦最大斜率约 13 LSB/入口, 三角固定 8 LSB/入口) 区分波形
//    3) SPI 发 0001 -> 频率上升; 0010 -> 依次切到三角/方波; 0100 -> led[3] 灭;
//       1000 -> 回默认 1kHz 正弦
//    4) led 一热码 = {使能, 方波, 三角, 正弦}, 与指令表一致
//
//  注: 频率计的闸门是 1 秒, 仿真里不做完整测量 (与原 tb_DAC904_TOP.v 的说明一致)。
//============================================================================
`timescale 1ns / 1ps

module tb_top_spi;

	//---- 板载 200MHz 差分时钟 (周期 5ns); 顶层内部 4 分频得到 50MHz ----
	reg sys_clk_p = 1'b0;
	reg sys_clk_n = 1'b1;
	always #2.5 sys_clk_p = ~sys_clk_p;
	always #2.5 sys_clk_n = ~sys_clk_n;

	//---- STM32 侧 / 其它输入 ----
	reg			SYS_RST = 1'b0;		//低有效
	reg			SCK   = 1'b0;
	reg			MOSI  = 1'b0;
	reg			NSS   = 1'b1;
	reg			comparator_out = 1'b0;
	wire			MISO;
	wire	[3:0]	led;

	//---- 被测顶层 ----
	wire				PD;
	wire				DAC_CLK;
	wire				BEEP_EN;
	wire	[13:0]	DAC_DATA;
	wire				LED;

	DAC904_TOP dut (
		.sys_clk_p		(sys_clk_p),
		.sys_clk_n		(sys_clk_n),
		.SYS_RST			(SYS_RST),
		.SCK				(SCK),
		.MOSI				(MOSI),
		.NSS				(NSS),
		.MISO				(MISO),
		.led				(led),
		.PD				(PD),
		.DAC_CLK			(DAC_CLK),
		.BEEP_EN			(BEEP_EN),
		.comparator_out	(comparator_out),
		.DAC_DATA		(DAC_DATA),
		.LED				(LED)
	);

	//--------------------------------------------------------------------
	// DAC 输出统计: 一个输出周期内的采样数 / 最大增量 / 不同增量个数 / 极值
	//--------------------------------------------------------------------
	reg			collect   = 1'b0;
	integer		n_samp    = 0;
	integer		max_delta = 0;
	integer		n_ndist   = 0;
	reg	[15:0]	dmap      = 16'd0;
	reg	[13:0]	dac_prev  = 14'd0;
	integer		d, ad;
	integer		vmin = 0;
	integer		vmax = 0;
	integer		v_seen = 0;
	integer		dac_edges = 0;

	always @(posedge DAC_CLK) dac_edges = dac_edges + 1;

	always @(posedge DAC_CLK)
		begin
			if (collect)
				begin
					d = {18'd0, DAC_DATA} - {18'd0, dac_prev};
					if (d < 0) ad = -d;
					else       ad =  d;
					if (ad > max_delta) max_delta = ad;
					if (ad > 0)
						begin
							if (ad < 16)
								begin
									if (!dmap[ad]) begin dmap[ad] = 1'b1; n_ndist = n_ndist + 1; end
								end
							else
								begin
									if (!dmap[15]) begin dmap[15] = 1'b1; n_ndist = n_ndist + 1; end
								end
						end
					if (!v_seen)
						begin
							vmin   = DAC_DATA;
							vmax   = DAC_DATA;
							v_seen = 1;
						end
					else
						begin
							if (DAC_DATA < vmin) vmin = DAC_DATA;
							if (DAC_DATA > vmax) vmax = DAC_DATA;
						end
					n_samp = n_samp + 1;
				end
			dac_prev <= DAC_DATA;
		end

	//--------------------------------------------------------------------
	// STM32 软件 SPI 主机行为模型 (与 tb_spi_cmd.v 相同)
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

			NSS = 1'b0;
			#200;
			for(i = 0; i < 8; i = i + 1)
				begin
					MOSI = t[7];
					t    = {t[6:0], 1'b0};
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

	//--------------------------------------------------------------------
	// 测一个完整输出周期 (以 DAC_DATA[13] 的相邻两个上升沿为界)
	//--------------------------------------------------------------------
	task measure;
		output	integer	p_ns;		//周期
		output	integer	ns;		//采样点数
		output	integer	md;		//最大 |相邻增量|
		output	integer	nd;		//不同 |增量| 值的个数
		output	integer	mn;		//最小值
		output	integer	mx;		//最大值
		integer				t0, t1;
		begin
			@(negedge DAC_DATA[13]);
			@(posedge DAC_DATA[13]);
			t0        = $time;
			n_samp    = 0;
			max_delta = 0;
			n_ndist   = 0;
			dmap      = 16'd0;
			v_seen    = 0;
			collect   = 1'b1;
			@(posedge DAC_DATA[13]);
			t1        = $time;
			collect   = 1'b0;

			p_ns = t1 - t0;
			ns   = n_samp;
			md   = max_delta;
			nd   = n_ndist;
			mn   = vmin;
			mx   = vmax;
		end
	endtask

	//--------------------------------------------------------------------
	// 记分板
	//--------------------------------------------------------------------
	integer		errors = 0;
	integer		p, ns, md, nd, mn, mx;
	reg	[7:0]	rx;
	reg	[7:0]	rx2;

	task chk_led;
		input	[3:0]		exp;
		input	integer	id;
		begin
			if (led !== exp)
				begin
					errors = errors + 1;
					$display("  [FAIL] #%0d led=%b (期望 %b)", id, led, exp);
				end
			else
				$display("  [ OK ] #%0d led=%b", id, led);
		end
	endtask

	task chk_period;
		input	integer	exp_ns;
		input	integer	tol_ns;
		input	integer	id;
		begin
			if ((p < (exp_ns - tol_ns)) || (p > (exp_ns + tol_ns)))
				begin
					errors = errors + 1;
					$display("  [FAIL] #%0d 周期=%0dns (期望 %0d±%0dns)", id, p, exp_ns, tol_ns);
				end
			else
				$display("  [ OK ] #%0d 周期=%0dns (%.3f kHz)", id, p, 1000000.0/p);
		end
	endtask

	//--------------------------------------------------------------------
	// 测试主体
	//--------------------------------------------------------------------
	initial
		begin
			$display("");
			$display("==== 仿真 B: 完整顶层 DAC904_TOP + SPI 命令 ====");

			SYS_RST = 1'b0;			//复位中
			SCK     = 1'b0;
			MOSI    = 1'b0;
			NSS     = 1'b1;
			#1000;
			SYS_RST = 1'b1;			//释放复位
			#500000;					//等 PLL 锁定 + 波形稳定

			//---- 1. PLL ----
			if (dac_edges < 1000)
				begin
					errors = errors + 1;
					$display("  [FAIL] #1 DAC_CLK 只翻转 %0d 次, PLL 未锁定?", dac_edges);
				end
			else
				$display("  [ OK ] #1 PLL 已锁定, 500us 内 DAC_CLK 翻转 %0d 次", dac_edges);

			//---- 2. 默认: 1kHz 正弦 ----
			$display("-- 默认: 1kHz 正弦 --");
			chk_led(4'b0110, 2);			//正弦 + 使能开 (低电平点亮)
			measure(p, ns, md, nd, mn, mx);
			chk_period(1000000, 50000, 3);
			if ((md < 10) || (nd < 4) || (mn > 200) || (mx < 16000))
				begin
					errors = errors + 1;
					$display("  [FAIL] #4 正弦波形特征不对: max_delta=%0d 不同增量=%0d min=%0d max=%0d", md, nd, mn, mx);
				end
			else
				$display("  [ OK ] #4 正弦特征: max_delta=%0d 不同增量=%0d min=%0d max=%0d 样点=%0d", md, nd, mn, mx, ns);

			//---- 3. 0001 x3 -> 4kHz ----
			$display("-- 发 0001 三次 (1k -> 4k) --");
			stm32_xfer(8'h01, 300, rx);
			stm32_xfer(8'h01, 300, rx);
			stm32_xfer(8'h01, 300, rx);
			chk_led(4'b0110, 5);
			measure(p, ns, md, nd, mn, mx);
			chk_period(250000, 15000, 6);

			//---- 4. 0010 -> 三角波 ----
			$display("-- 发 0010 切三角波 + 0010 切方波 --");
			stm32_xfer(8'h02, 300, rx);
			chk_led(4'b0101, 7);			//三角
			measure(p, ns, md, nd, mn, mx);
			chk_period(250000, 15000, 8);
			// 三角波: 每入口固定 8 LSB, 只在波峰/波谷转折处会出现一个不同的步进(0~2 种)
			if ((md != 8) || (nd > 3))
				begin
					errors = errors + 1;
					$display("  [FAIL] #9 三角波特征不对: max_delta=%0d(期望8) 不同增量=%0d(期望<=3)", md, nd);
				end
			else
				$display("  [ OK ] #9 三角波特征: max_delta=%0d 不同增量=%0d (线性斜坡)", md, nd);

			//---- 5. 0010 -> 方波 ----
			stm32_xfer(8'h02, 300, rx);
			chk_led(4'b0011, 10);			//方波
			measure(p, ns, md, nd, mn, mx);
			chk_period(250000, 15000, 11);
			if (md < 1000 || mn > 1 || mx < 16000)
				begin
					errors = errors + 1;
					$display("  [FAIL] #12 方波特征不对: max_delta=%0d min=%0d max=%0d", md, mn, mx);
				end
			else
				$display("  [ OK ] #12 方波特征: max_delta=%0d min=%0d max=%0d (两电平)", md, mn, mx);

			//---- 6. 0100 关频率计使能 ----
			stm32_xfer(8'h04, 300, rx);
			chk_led(4'b1011, 13);			//方波 + 使能关
			stm32_xfer(8'h04, 300, rx);
			chk_led(4'b0011, 14);

			//---- 7. 1000 软复位回默认 ----
			$display("-- 发 1000 软复位 --");
			stm32_xfer(8'h08, 300, rx);
			chk_led(4'b0110, 15);
			measure(p, ns, md, nd, mn, mx);
			chk_period(1000000, 50000, 16);
			if ((md < 10) || (nd < 4))
				begin
					errors = errors + 1;
					$display("  [FAIL] #17 软复位后不是正弦: max_delta=%0d 不同增量=%0d", md, nd);
				end
			else
				$display("  [ OK ] #17 软复位后回到 1kHz 正弦: max_delta=%0d 不同增量=%0d", md, nd);

			//---- 8. MISO 回环 (STM32 握手判据) ----
			stm32_xfer(8'h03, 300, rx2);
			if (rx2 !== 8'h03)
				begin
					errors = errors + 1;
					$display("  [FAIL] #18 顶层 MISO 回环: tx=00000011 rx=%08b", rx2);
				end
			else
				$display("  [ OK ] #18 顶层 MISO 回环正常 (STM32 会显示通信成功)");

			$display("");
			$display("==== 结果: 失败项 %0d ====", errors);
			if (errors == 0)
				$display("PASS: 顶层集成仿真全部通过");
			else
				$display("FAIL: 存在错误");

			$finish;
		end

endmodule
