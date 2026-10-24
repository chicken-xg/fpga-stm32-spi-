// -----------------------------------------------------------------------------
// ROM_Sin : Altera altsyncram (4096 x 14 单口 ROM, Sin_Wave.mif) 的 Xilinx 等价实现
//
// 端口与 Quartus 生成的 ROM_Sin 一致，DAC904_TOP 无需修改即可直接实例化。
// 内部例化 Block Memory Generator (blk_mem_gen v8.4) 单口 ROM，
// 初始化文件为 src/rom/Sin_Wave.coe (由 Sin_Wave.mif 转换)。
// 输出打一拍 (Register_PortA_Output_of_Memory_Primitives = true)，与原 IP 的
// outdata_reg_a = "CLOCK0" 一致。
// -----------------------------------------------------------------------------
module ROM_Sin(
	input  wire        clock,
	input  wire [11:0] address,
	output wire [13:0] q
);

	rom_sin u_rom_sin (
		.clka  (clock  ),
		.addra (address),
		.douta (q      )
	);

endmodule
