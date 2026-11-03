module btn_debounce #(
    parameter CLK_FREQ = 50_000_000,  // 系统时钟 50MHz
    parameter DEBOUNCE_MS = 10       // 去抖时间 10ms
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [3:0] btn_in,         // 4 个按键输入
    output reg  [3:0] btn_out,        // 去抖后的稳定状态
    output reg  [3:0] btn_press,      // 按下瞬间脉冲
    output reg  [3:0] btn_release     // 新增：松开瞬间脉冲
);

    // 1. 产生 10ms 滴答定时器
    localparam CNT_MAX = (CLK_FREQ / 1000) * DEBOUNCE_MS;
    reg [31:0] cnt;
    reg tick_10ms;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
            tick_10ms <= 0;
        end else if (cnt == CNT_MAX - 1) begin
            cnt <= 0;
            tick_10ms <= 1;
        end else begin
            cnt <= cnt + 1;
            tick_10ms <= 0;
        end
    end

    // 2. 信号打两拍，同步异步输入
    reg [3:0] btn_r0, btn_r1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_r0 <= 4'hF;
            btn_r1 <= 4'hF;
        end else begin
            btn_r0 <= btn_in;
            btn_r1 <= btn_r0;
        end
    end

    // 3. 每 10ms 采样一次
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_out <= 4'hF;
        end else if (tick_10ms) begin
            btn_out <= btn_r1; 
        end
    end

    // 4. 提取边沿，产生脉冲
    reg [3:0] btn_out_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            btn_out_r <= 4'hF;
        else        
            btn_out_r <= btn_out;
    end

    // 产生按键按下脉冲 (下降沿)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            btn_press <= 4'd0;
        else
            btn_press <= (~btn_out) & btn_out_r; 
    end

    // 产生按键松开脉冲 (上升沿)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            btn_release <= 4'd0;
        else
            btn_release <= btn_out & (~btn_out_r); 
    end

endmodule