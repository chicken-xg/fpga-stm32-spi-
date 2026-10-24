module seg7_hex8(
    input       [31:0] x,
    input              clk,
    input              clr,
    output   [6:0]  a_to_g,
    output   [7:0]  an,
    output wire        dp 
   );

  wire [2:0]  s;
  wire [7:0]  aen;
  reg  [3:0]  digit;
  reg  [19:0] clkdiv;
  reg   [6:0]  a_to_g_r;
  reg   [7:0]  an_r;

  assign an=~an_r;
  assign a_to_g =~a_to_g_r;
  assign dp  = 1'b1;
  assign aen = 8'b1111_1111; 
  assign s   = clkdiv[19:17];
  
  always @(posedge clk or negedge clr) 
    begin
      if ( clr == 0)
        clkdiv <= 0;
      else
        clkdiv <= clkdiv+1;
    end
  
  always @(posedge clk)
    case(s)
        3'd7:    digit = x[31:28]; 
        3'd6:    digit = x[27:24]; 
        3'd5:    digit = x[23:20];  
        3'd4:    digit = x[19:16]; 
        3'd3:    digit = x[15:12]; 
        3'd2:    digit = x[11:8]; 
        3'd1:    digit = x[7:4];  
        3'd0:    digit = x[3:0]; 
        default: digit = x[3:0];
    endcase
    
  always @(*)
    begin
      an_r = 8'b0000_0000;
      if(aen[s] == 1)
         an_r[s]  =  1;
    end

  always @(*)
    case(digit)
        0:       a_to_g_r = 7'b0111111;
        1:       a_to_g_r = 7'b0000110;
        2:       a_to_g_r = 7'b1011011;
        3:       a_to_g_r = 7'b1001111;
        4:       a_to_g_r = 7'b1100110;
        5:       a_to_g_r = 7'b1101101;
        6:       a_to_g_r = 7'b1111101;
        7:       a_to_g_r = 7'b0000111;
        8:       a_to_g_r = 7'b1111111;
        9:       a_to_g_r = 7'b1101111;
        'hA:     a_to_g_r = 7'b1110111;
        'hB:     a_to_g_r = 7'b1111100;
        'hC:     a_to_g_r = 7'b1100001;
        'hD:     a_to_g_r = 7'b1011110; 
        'hE:     a_to_g_r = 7'b1111001; 
        'hF:     a_to_g_r = 7'b1110001;
        default: a_to_g_r = 7'b1111111;
    endcase
	 

endmodule
