// 32-bit phase accumulator with a 256-point sine ROM.
// Square, saw and triangle are generated from the phase word.
module dds_multi (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick,
    input  wire        [31:0] fcw,
    input  wire        [1:0]  timbre,
    output reg  signed [15:0] sample
);

    reg  [31:0] phase;
    wire [7:0]  addr = phase[31:24];
    wire [15:0] rom_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            phase <= 32'd0;
        else if (tick)
            phase <= phase + fcw;
    end

    rom_wave_sine u_rom (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (addr),
        .data  (rom_data)
    );

    wire [15:0] tri_u =
        phase[31] ? ~phase[31:16] : phase[31:16];
    wire signed [16:0] tri17 =
        $signed({1'b0, tri_u}) - 17'sd16384;

    reg signed [15:0] shaped;
    always @(*) begin
        case (timbre)
            2'd0:    shaped = $signed(rom_data);
            2'd1:    shaped = phase[31] ? -16'sd24000 : 16'sd24000;
            2'd2:    shaped = $signed(phase[31:16]);
            default: shaped = tri17[15:0];
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sample <= 16'sd0;
        else
            sample <= shaped;
    end

endmodule
