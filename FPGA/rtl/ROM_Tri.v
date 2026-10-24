// -----------------------------------------------------------------------------
// ROM_Tri : Altera altsyncram (4096 x 14 单口 ROM, Tri_Wave.mif) 的 Xilinx 等价实现
//
// 端口与 Quartus 生成的 ROM_Tri 一致，DAC904_TOP 无需修改即可直接实例化。
// 内部例化 Block Memory Generator (blk_mem_gen v8.4) 单口 ROM，
// 初始化文件为 src/rom/Tri_Wave.coe (由 Tri_Wave.mif 转换)。
//
// 注意: 原 Altera IP 的 outdata_reg_a = "UNREGISTERED"，而 Xilinx BRAM ROM 强制
// 寄存器输出，因此三角波通路比原设计多一个 165MHz 时钟(约 6ns)的相位延迟。
// 若需严格复刻，可改用 dist_mem_gen (分布式 RAM, 异步读) 实现本模块。
// -----------------------------------------------------------------------------
module ROM_Tri(
	input  wire        clock,
	input  wire [11:0] address,
	output wire [13:0] q
);

	rom_tri u_rom_tri (
		.clka  (clock  ),
		.addra (address),
		.douta (q      )
	);

endmodule
