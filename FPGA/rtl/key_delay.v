module key_delay(
	input 	wire	clk			,
	input 	wire	kin			,
	output	wire	key_out
);

localparam del = (165_000_000 / 50) - 1;	//clk = 50MHz, del 20ms.

reg		[31:0] 	kh;
reg		[31:0]	kl;
reg						kout;

//低电平消抖
always@(posedge clk)
begin
	if(!kin)
		kl <= kl + 1'b1;
	else 
		kl <= 32'd0;
end
 
//高电平消抖
always@(posedge clk)
begin
	if(kin)begin
		kh <= kh + 1'b1;
	end
	else 
		kh <= 32'd0;
end

always@(posedge clk)
begin
	if(kh > del)begin
		kout <= 1'b1;
	end
	else if(kl > del)begin
		kout <= 1'b0;
	end
	else begin
		kout <= kout;
	end
end

assign	key_out = kout;

endmodule 