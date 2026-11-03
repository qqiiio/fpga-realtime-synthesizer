// One synth voice: DDS + independent ADSR + DSP-free envelope gain.
module voice_lut (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick,
    input  wire        [31:0] fcw,
    input  wire        [1:0]  timbre,
    input  wire        [6:0]  velocity,
    input  wire               trigger,
    input  wire               gate,
    output wire signed [15:0] out
);

    wire signed [15:0] osc;
    wire        [15:0] env;

    dds_multi u_dds (
        .clk    (clk),
        .rst_n  (rst_n),
        .tick   (tick),
        .fcw    (fcw),
        .timbre (timbre),
        .sample (osc)
    );

    adsr_event u_adsr (
        .clk     (clk),
        .rst_n   (rst_n),
        .tick    (tick),
        .trigger (trigger),
        .gate    (gate),
        .env     (env)
    );

    // Shift-add implements osc * (env[15:11] / 32) without a DSP block.
    function signed [17:0] mul_gain;
        input signed [15:0] s;
        input        [4:0]  g;
        reg   signed [17:0] a;
        reg   signed [17:0] sx;
        begin
            sx = {{2{s[15]}}, s};
            a  = 18'sd0;
            if (g[4]) a = a + sx;
            if (g[3]) a = a + (sx >>> 1);
            if (g[2]) a = a + (sx >>> 2);
            if (g[1]) a = a + (sx >>> 3);
            if (g[0]) a = a + (sx >>> 4);
            mul_gain = a;
        end
    endfunction

    // 5x5-bit velocity/envelope product implemented with shifts and adds.
    function [9:0] mul5x5;
        input [4:0] a;
        input [4:0] b;
        reg   [9:0] p;
        begin
            p = 10'd0;
            if (b[4]) p = p + ({5'd0, a} << 4);
            if (b[3]) p = p + ({5'd0, a} << 3);
            if (b[2]) p = p + ({5'd0, a} << 2);
            if (b[1]) p = p + ({5'd0, a} << 1);
            if (b[0]) p = p + {5'd0, a};
            mul5x5 = p;
        end
    endfunction

    wire [9:0] gain_product = mul5x5(env[15:11], velocity[6:2]);
    wire [4:0] gain = gain_product[9:5];
    wire signed [17:0] scaled = mul_gain(osc, gain);
    assign out = scaled[15:0];

endmodule
