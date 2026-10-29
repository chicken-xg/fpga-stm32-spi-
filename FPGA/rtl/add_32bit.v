module add_32bit (
	input 	wire			clk	 ,
	input 	wire			rst	 ,
	input 	wire	[31:0] 	fr_k ,
	output 	wire	[11:0] 	adder
);

reg  [31:0] add;

always @(posedge clk) 
begin
	if (!rst) 
	begin
		add <= 32'd0;
	end
	else 
	begin
		add <= add + fr_k;
	end
end

assign   adder = add[31:20];

endmodule 