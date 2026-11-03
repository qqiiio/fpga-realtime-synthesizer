// B2 candidate: IIR + delay + chorus + two-tap reverb + soft limiter.
// Dry audio is never muted. Each wet path is enabled only after the source
// address of its BSRAM line has been written at least once.
module fx_chain_full (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick,
    input  wire signed [15:0] din,
    input  wire        [1:0]  mode,
    output wire signed [15:0] dout
);

    //------------------------------------------------------------------
    // IIR low-pass.
    //------------------------------------------------------------------
    reg  signed [16:0] lpf1;
    reg  signed [16:0] lpf2;
    wire signed [16:0] din17 = din;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lpf1 <= 17'sd0;
            lpf2 <= 17'sd0;
        end
        else if (tick) begin
            lpf1 <= lpf1 + ((din17 - lpf1) >>> 1);
            lpf2 <= lpf2 + ((lpf1  - lpf2) >>> 1);
        end
    end

    wire signed [15:0] lpf_out = lpf2[15:0];

    // One sample counter drives wet-path validity.
    reg [15:0] sample_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sample_count <= 16'd0;
        else if (tick && sample_count != 16'd65535)
            sample_count <= sample_count + 1'b1;
    end

    wire delay_ready  = (sample_count >= 16'd16385);
    wire chorus_ready = (sample_count >= 16'd1025);
    wire verb_ready   = (sample_count >= 16'd6145);

    //------------------------------------------------------------------
    // 350 ms delay line, no feedback. The dry path is always audible.
    //------------------------------------------------------------------
    reg  [14:0]        echo_wr;
    reg  signed [15:0] echo_mem [0:32767];
    reg  signed [15:0] echo_d;
    wire [14:0]        echo_rd = echo_wr - 15'd16384;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            echo_wr <= 15'd0;
            echo_d  <= 16'sd0;
        end
        else if (tick) begin
            echo_mem[echo_wr] <= lpf_out;
            echo_d            <= echo_mem[echo_rd];
            echo_wr           <= echo_wr + 1'b1;
        end
    end

    //------------------------------------------------------------------
    // 22 ms chorus delay with 1.4 Hz triangular modulation.
    //------------------------------------------------------------------
    reg  [10:0]        cho_wr;
    reg  signed [15:0] cho_mem [0:2047];
    reg  signed [15:0] cho_d;
    reg  [15:0]        lfo_cnt;
    wire [7:0]         lfo_tri =
        lfo_cnt[14] ? ~lfo_cnt[13:6] : lfo_cnt[13:6];
    wire [10:0]        cho_rd =
        cho_wr - 11'd1024 + {3'b000, lfo_tri};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cho_wr  <= 11'd0;
            cho_d   <= 16'sd0;
            lfo_cnt <= 16'd0;
        end
        else if (tick) begin
            cho_mem[cho_wr] <= lpf_out;
            cho_d           <= cho_mem[cho_rd];
            cho_wr          <= cho_wr + 1'b1;
            lfo_cnt         <= lfo_cnt + 1'b1;
        end
    end

    //------------------------------------------------------------------
    // Two-tap early-reflection reverb.
    //------------------------------------------------------------------
    reg  [12:0]        c1_wr, c2_wr;
    reg  signed [15:0] c1_mem [0:8191];
    reg  signed [15:0] c2_mem [0:8191];
    reg  signed [15:0] c1_d, c2_d;
    wire [12:0]        c1_rd = c1_wr - 13'd4096;
    wire [12:0]        c2_rd = c2_wr - 13'd6144;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c1_wr <= 13'd0;
            c2_wr <= 13'd0;
            c1_d  <= 16'sd0;
            c2_d  <= 16'sd0;
        end
        else if (tick) begin
            c1_mem[c1_wr] <= lpf_out;
            c2_mem[c2_wr] <= lpf_out;
            c1_d          <= c1_mem[c1_rd];
            c2_d          <= c2_mem[c2_rd];
            c1_wr         <= c1_wr + 1'b1;
            c2_wr         <= c2_wr + 1'b1;
        end
    end

    wire signed [16:0] verb_sum = c1_d + c2_d;

    //------------------------------------------------------------------
    // Dry/wet selection.
    //------------------------------------------------------------------
    reg signed [16:0] mix;
    always @(*) begin
        case (mode)
            2'd0: mix = lpf_out;
            2'd1: mix = lpf_out +
                        (delay_ready
                         ? ((echo_d >>> 1) + (echo_d >>> 2))
                         : 17'sd0);
            2'd2: mix = lpf_out +
                        (chorus_ready ? (cho_d >>> 1) : 17'sd0);
            default: mix = lpf_out +
                           (verb_ready
                            ? ((c1_d >>> 1) + (c2_d >>> 1))
                            : 17'sd0);
        endcase
    end

    //------------------------------------------------------------------
    // Soft limiter: only samples above |24576| are compressed.
    //------------------------------------------------------------------
    wire signed [16:0] knee_p =
        17'sd24576 + ((mix - 17'sd24576) >>> 1);
    wire signed [16:0] knee_n =
        -17'sd24576 + ((mix + 17'sd24576) >>> 1);
    reg signed [15:0] sat;

    always @(*) begin
        if (mix > 17'sd24576)
            sat = (knee_p > 17'sd32767) ? 16'sd32767 : knee_p[15:0];
        else if (mix < -17'sd24576)
            sat = (knee_n < -17'sd32768) ? -16'sd32768 : knee_n[15:0];
        else
            sat = mix[15:0];
    end

    assign dout = sat;

endmodule
