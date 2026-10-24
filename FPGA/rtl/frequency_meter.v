module simple_freq_meter(
    input             clk,
    input             rst_n,
    input             freq_in,
    input             meas_en,          // 使能输入
    output reg [31:0] frequency
);

localparam CLK_FREQ = 32'd165_000_000;
localparam GATE_TIME = 32'd165_000_000;
localparam DEBOUNCE_CYCLES = 4;

reg gate_open;
reg [31:0] gate_cnt;
reg [31:0] std_cnt;
reg [31:0] sig_cnt;
reg [31:0] sig_cnt_latch;
reg [31:0] std_cnt_latch;
reg measure_done_reg;
reg [63:0] temp_mul;

reg [DEBOUNCE_CYCLES-1:0] sync_shift;
reg freq_in_debounced;
reg freq_in_debounced_prev;
reg freq_in_rising;

// 去抖动
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sync_shift <= {DEBOUNCE_CYCLES{1'b0}};
        freq_in_debounced <= 1'b0;
    end else begin
        sync_shift <= {sync_shift[DEBOUNCE_CYCLES-2:0], freq_in};
        if (&sync_shift)               freq_in_debounced <= 1'b1;
        else if (~(|sync_shift))       freq_in_debounced <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_in_debounced_prev <= 1'b0;
        freq_in_rising <= 1'b0;
    end else begin
        freq_in_debounced_prev <= freq_in_debounced;
        freq_in_rising <= freq_in_debounced & (~freq_in_debounced_prev);
    end
end

// 闸门控制
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gate_open <= 1'b0;
        gate_cnt <= 32'd0;
        measure_done_reg <= 1'b0;
    end else if (!meas_en) begin
        gate_open <= 1'b0;
        gate_cnt <= 32'd0;
        measure_done_reg <= 1'b0;
    end else begin
        measure_done_reg <= 1'b0;
        if (!gate_open) begin
            if (freq_in_rising) begin
                gate_open <= 1'b1;
                gate_cnt <= 32'd0;
            end
        end else begin
            if (gate_cnt < GATE_TIME - 1)
                gate_cnt <= gate_cnt + 1'b1;
            else if (freq_in_rising) begin
                gate_open <= 1'b0;
                measure_done_reg <= 1'b1;
            end
        end
    end
end

// 标准时钟计数（使能复位）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        std_cnt <= 32'd0;
        std_cnt_latch <= 32'd0;
    end else if (!meas_en) begin
        std_cnt <= 32'd0;
        std_cnt_latch <= 32'd0;
    end else begin
        if (gate_open)
            std_cnt <= std_cnt + 1'b1;
        else if (measure_done_reg) begin
            std_cnt_latch <= std_cnt;
            std_cnt <= 32'd0;
        end
    end
end

// 被测信号计数（使能复位）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sig_cnt <= 32'd0;
        sig_cnt_latch <= 32'd0;
    end else if (!meas_en) begin
        sig_cnt <= 32'd0;
        sig_cnt_latch <= 32'd0;
    end else begin
        if (gate_open && freq_in_rising)
            sig_cnt <= sig_cnt + 1'b1;
        else if (measure_done_reg) begin
            sig_cnt_latch <= sig_cnt;
            sig_cnt <= 32'd0;
        end
    end
end

// 频率计算（使能时输出0）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        temp_mul <= 64'd0;
        frequency <= 32'd0;
    end else if (!meas_en) begin
        frequency <= 32'd0;
    end else begin
        if (measure_done_reg && (std_cnt_latch > 32'd0)) begin
            temp_mul <= {32'd0, sig_cnt_latch} * CLK_FREQ;
            frequency <= temp_mul / {32'd0, std_cnt_latch};
        end
    end
end

endmodule