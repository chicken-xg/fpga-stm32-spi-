module key_con (
	input 	wire 					clk		, 
	input 	wire 					rst_n		,
	input 	wire 					key1_in	,
	input 	wire 					key2_in	,
	input		wire					key3_in	,
	input		wire					key4_in	,
	output  wire	[1:0] 	   sel_wave ,
	output  wire	[31:0]    	fre_k    , 
	output wire        meas_en 
);  

reg  [31:0] fre;
reg  [1:0]	cnt;
reg  [1:0]  sel;
reg        meas_en_reg;

wire key1_out;
wire key2_out;
wire key3_out;
wire key4_out;

wire freq_sel;

// delay 
key_delay u_key1_delay(
	.clk		(clk			),
	.kin		(key1_in	),
	.key_out(key1_out	)
);

// delay 
key_delay u_key2_delay(
	.clk		(clk			),
	.kin		(key2_in	),
	.key_out(key2_out	)
);

// delay 
key_delay u_key3_delay(
	.clk		(clk			),
	.kin		(key3_in	),
	.key_out(key3_out	)
);
key_delay u_key4_delay(
	.clk		(clk			),
	.kin		(key4_in	),
	.key_out(key4_out	)
);

always @(negedge key4_out or negedge rst_n) begin
    if (!rst_n)
        meas_en_reg <= 1'b1;        // 默认使能开启
    else
        meas_en_reg <= ~meas_en_reg;
end
assign meas_en = meas_en_reg;
assign freq_sel = (~key1_out) | (~key3_out);

// 频率调整
always @(posedge freq_sel or negedge rst_n) 
begin
	if(!rst_n)begin
		fre <= 32'd26031; //1Khz
	end
	else if(key1_out)begin	
		if(fre < 32'd260310)					// 10Khz
			fre <= fre + 32'd26031;			// 步进1Khz
		else if(fre < 32'd2603100)		// 100KHz
			fre <= fre + 32'd260310;		// 步进10Khz
		else if(fre < 32'd26031000)		// 1Mhz
			fre <= fre + 32'd2603100;		// 步进100Khz
		else if(fre < 32'd2603100000) // 100Mhz 
			fre <= fre + 32'd26031000;  // 步进1Mhz
		else
			fre <= 32'd26031;	
	end
	else if(key3_out)begin
		if(fre > 32'd260310000)				// 10Mhz
			fre <= fre - 32'd26031000; 	// 步进1Mhz		
		else if(fre > 32'd2603100)		// 100Khz
			fre <= fre - 32'd2603100; 	// 步进100Khz
		else if(fre > 32'd260310)			// 10KHz
			fre <= fre - 32'd260310;		// 步进10Khz
		else if(fre > 32'd26031)			// 1Khz
			fre <= fre - 32'd26031;			// 步进1Khz	
		else
			fre <= 32'd26031;	
	end
	else begin
		fre <= fre;
	end
end

// 输出波形选择
always @(negedge key2_out or negedge rst_n) 
begin 
	if(!rst_n)begin
		cnt <= 2'd0;
	end
	else if(cnt < 3) begin
		cnt <= cnt + 1'b1;
	end
	else begin 
		cnt <= 2'd0;
	end 
end

always @(posedge clk) begin 
	case (cnt) 
		2'b00 : sel <= 2'b00;
		2'b01 : sel <= 2'b01;
		2'b10 : sel <= 2'b10;
		default : sel <= 2'b00;
	endcase 
end 

assign  fre_k = fre;
assign  sel_wave = sel;

endmodule 