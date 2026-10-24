// 二进制转BCD模块 (32位输入 -> 32位BCD输出)
module bin2bcd_32 (
    input      [31:0] bin,
    output reg [31:0] bcd
);
    integer i;
    always @(*) begin
        bcd = 0;
        for (i = 0; i < 32; i = i + 1) begin
            if (bcd[3:0]   >= 5) bcd[3:0]   = bcd[3:0]   + 3;
            if (bcd[7:4]   >= 5) bcd[7:4]   = bcd[7:4]   + 3;
            if (bcd[11:8]  >= 5) bcd[11:8]  = bcd[11:8]  + 3;
            if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
            if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;
            if (bcd[23:20] >= 5) bcd[23:20] = bcd[23:20] + 3;
            if (bcd[27:24] >= 5) bcd[27:24] = bcd[27:24] + 3;
            if (bcd[31:28] >= 5) bcd[31:28] = bcd[31:28] + 3;
            bcd = {bcd[30:0], bin[31-i]};
        end
    end
endmodule