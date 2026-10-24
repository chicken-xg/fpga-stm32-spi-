// -----------------------------------------------------------------------------
// PLL_CLK : Altera altpll (50MHz -> 165MHz) 的 Xilinx 等价实现
//
// 端口与 Quartus 生成的 PLL_CLK 一致，DAC904_TOP 无需修改即可直接实例化。
// 内部例化 Clocking Wizard (clk_wiz v6.0, MMCM)。
//
//   inclk0 : 50MHz  参考时钟，接 SYS_CLK
//   areset : 高有效复位，原顶层接 !SYS_RST
//   c0     : 165MHz 输出，接 CLK_165M
//
// 原始 Altera 配置: clk0_multiply_by = 33, clk0_divide_by = 10 -> 50 * 33 / 10 = 165MHz
// 对应 MMCM 解: 输入分频 D=2, 反馈倍频 M=33 (VCO = 825MHz), CLKOUT0 分频 = 5
// -----------------------------------------------------------------------------
module PLL_CLK(
	input  wire areset,
	input  wire inclk0,
	output wire c0
);

	wire clk_out1;

	pll_165m u_pll_165m (
		.reset    (areset  ),
		.clk_in1  (inclk0  ),
		.clk_out1 (clk_out1)
	);

	assign c0 = clk_out1;

endmodule
