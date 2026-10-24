// ²¨ĞÎÑ¡Ôñ
module sel_wave(
	input 	wire					clk		,
	input 	wire					rst_n	,
	input 	wire	[1:0] 	sel		,
	input 	wire	[13:0] 	da_ina,
	input 	wire	[13:0] 	da_inb,
	input 	wire	[13:0] 	da_inc,
	output 	wire	[13:0] 	da_out
);

reg [13:0] da_out_reg;

assign da_out = da_out_reg;

always @(posedge clk or negedge rst_n)
begin
	if(!rst_n)
	begin
		da_out_reg <= 14'd0;
	end
	else
	begin
		case(sel)
			2'b00 : da_out_reg <= da_ina;
			2'b01 : da_out_reg <= da_inb;
			2'b10 : da_out_reg <= da_inc;
			default: da_out_reg <= da_ina;
		endcase
	end
end

endmodule 