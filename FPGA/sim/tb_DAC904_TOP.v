// -----------------------------------------------------------------------------
// DAC904_TOP 行为级测试平台 (移植后修正版)
//
// 原 Quartus 工程中的 tb_DAC904_TOP.v 与当前顶层不匹配:
//   * KEY_IN 只声明了 3 位, 顶层实际是 4 位
//   * 未连接 PD / BEEP_EN / comparator_out / a_to_g / an / dp / LED
//   * 未驱动 comparator_out (频率计输入)
// 本文件按顶层当前端口列表重写。
//
// 注意: 频率计的闸门时间是 165MHz 下的 1 秒 (GATE_TIME = 165_000_000),
// 在 XSim 中完整跑完一次测量不现实。本测试平台只做短程验证:
//   1) PLL 锁定后 CLK_165M 正常翻转 (DAC_CLK 有输出)
//   2) 键值切换后 DAC_DATA 跟随 ROM 数据变化
// 完整频率计功能请在板卡上验证。
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_DAC904_TOP;

	reg         SYS_CLK;
	reg         SYS_RST;
	reg  [3:0]  KEY_IN;
	reg         comparator_out;

	wire        PD;
	wire        DAC_CLK;
	wire        BEEP_EN;
	wire [13:0] DAC_DATA;
	wire [6:0]  a_to_g;
	wire [7:0]  an;
	wire        dp;
	wire        LED;

	// 50MHz 系统时钟 (20ns 周期)
	initial begin
		SYS_CLK = 1'b0;
		forever #10 SYS_CLK = ~SYS_CLK;
	end

	// 比较器输入: 约 1MHz 方波, 仅用于观察频率计是否被驱动
	initial begin
		comparator_out = 1'b0;
		forever #500 comparator_out = ~comparator_out;
	end

	integer cycle_cnt;
	always @(posedge DAC_CLK) cycle_cnt <= cycle_cnt + 1;

	initial begin
		cycle_cnt = 0;
		SYS_RST  = 1'b0;      // 复位有效 (低有效)
		KEY_IN   = 4'b1111;   // 按键默认高电平 (按下为低)

		#1000;
		SYS_RST = 1'b1;       // 释放复位, PLL 开始锁定
		#20000;

		$display("[%0t] after reset: DAC_CLK=%b LED=%b DAC_DATA=%0d", $time, DAC_CLK, LED, DAC_DATA);

		// key2: 切换波形 (正弦 -> 三角)
		KEY_IN[1] = 1'b0; #1000; KEY_IN[1] = 1'b1;
		#20000;
		$display("[%0t] after key2:  DAC_DATA=%0d (expect triangle ROM data)", $time, DAC_DATA);

		// key1: 提高频率
		KEY_IN[0] = 1'b0; #1000; KEY_IN[0] = 1'b1;
		#20000;
		$display("[%0t] after key1:  DAC_DATA=%0d", $time, DAC_DATA);

		if (cycle_cnt == 0) begin
			$display("FAIL: 165MHz PLL output (DAC_CLK) did not toggle");
		end
		else begin
			$display("PASS: DAC_CLK toggled %0d times at 165MHz", cycle_cnt);
		end

		$finish;
	end

endmodule
