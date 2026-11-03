// A+B standalone board integration.
// A controls 4 note buttons, pitch bend switches, LEDs and 7-segment display.
// B synthesizes 32 voices and feeds the known-good PT8211 I2S driver.
module top_fx (
    input  wire       sys_clk,       // V22, 50 MHz
    input  wire       sys_rst_n,     // AA13, active low
    input  wire [7:0] btn,
    output wire [7:0] led,
    output wire [6:0] seg,
    output wire       sel,
    output wire       HP_BCK,
    output wire       HP_WS,
    output wire       HP_DIN,
    output wire       PA_EN
);

    // Power-on reset for the A event domain.
    reg [7:0] rst_cnt;
    always @(posedge sys_clk) begin
        if (!sys_rst_n)
            rst_cnt <= 8'd0;
        else if (rst_cnt < 8'd100)
            rst_cnt <= rst_cnt + 1'b1;
    end
    wire sys_rst = sys_rst_n & (rst_cnt == 8'd100);

    // S3 and S4 select the B2 effect:
    // 0 = IIR dry, 1 = delay, 2 = chorus, 3 = two-tap reverb.
    // The PMOD switches are active-high in this build:
    // S3=ON selects bit 0, S4=ON selects bit 1.
    wire [1:0] fx_mode = {btn[6], btn[4]};
    reg [6:0] fx_seg;
    always @(*) begin
        case (fx_mode)
            2'd0: fx_seg = 7'h40;
            2'd1: fx_seg = 7'h79;
            2'd2: fx_seg = 7'h24;
            default: fx_seg = 7'h30;
        endcase
    end

    // A: debounce and note allocation.
    wire [3:0] btn_press;
    wire [3:0] btn_release;
    wire [3:0] btn_stable;

    btn_debounce #(
        .CLK_FREQ(50_000_000),
        .DEBOUNCE_MS(10)
    ) u_debounce (
        .clk         (sys_clk),
        .rst_n       (sys_rst),
        .btn_in      ({btn[7], btn[5], btn[2], btn[0]}),
        .btn_out     (btn_stable),
        .btn_press   (btn_press),
        .btn_release (btn_release)
    );

    // S1/S2 provide slow pitch-bend up/down.
    reg [7:0]  pitch_bend_val;
    reg [31:0] bend_cnt;
    always @(posedge sys_clk or negedge sys_rst) begin
        if (!sys_rst) begin
            pitch_bend_val <= 8'd64;
            bend_cnt <= 32'd0;
        end
        else begin
            bend_cnt <= bend_cnt + 32'd1;
            if (bend_cnt == 32'd5_000_000) begin
                bend_cnt <= 32'd0;
                if (btn[1] == 1'b0) begin
                    if (pitch_bend_val < 8'd127)
                        pitch_bend_val <= pitch_bend_val + 1'b1;
                end
                else if (btn[3] == 1'b0) begin
                    if (pitch_bend_val > 8'd0)
                        pitch_bend_val <= pitch_bend_val - 1'b1;
                end
            end
        end
    end

    wire [7:0] note_id;
    wire [7:0] velocity;
    wire       note_on;
    wire       note_off;
    wire [4:0] voice_id;
    wire [7:0] pitch_bend;
    wire [7:0] vibrato;

    note_allocator u_note_alloc (
        .clk          (sys_clk),
        .rst_n        (sys_rst),
        .key_press    (btn_press),
        .key_release  (btn_release),
        .pitch_bend_in(pitch_bend_val),
        .vibrato_in   (8'd0),
        .note_id      (note_id),
        .velocity     (velocity),
        .note_on      (note_on),
        .note_off     (note_off),
        .voice_id     (voice_id),
        .pitch_bend   (pitch_bend),
        .vibrato      (vibrato)
    );

    // Existing A display functions.
    reg [6:0] seg_ones;
    always @(*) begin
        case (note_id % 10)
            0: seg_ones = 7'h40;
            1: seg_ones = 7'h79;
            2: seg_ones = 7'h24;
            3: seg_ones = 7'h30;
            4: seg_ones = 7'h19;
            5: seg_ones = 7'h12;
            6: seg_ones = 7'h02;
            7: seg_ones = 7'h78;
            8: seg_ones = 7'h00;
            9: seg_ones = 7'h10;
            default: seg_ones = 7'h7f;
        endcase
    end
    assign seg = fx_seg;
    assign sel = 1'b0;
    assign led[7:4] = ~pitch_bend_val[7:4];
    assign led[3:0] = btn_stable;

    // B audio clock path matches the already verified 18 baseline.
    wire clk_osc_w;
    wire clk_6m_w;
    wire clk_1p5m_w;

    Gowin_OSC u_osc (
        .oscout(clk_osc_w)
    );
    Gowin_PLL u_pll (
        .clkout0(clk_6m_w),
        .clkin  (clk_osc_w)
    );
    Gowin_CLKDIV u_div (
        .clkout (clk_1p5m_w),
        .hclkin (clk_6m_w),
        .resetn (sys_rst)
    );

    reg [4:0] audio_frame_cnt;
    wire audio_tick = (audio_frame_cnt == 5'd0);
    always @(posedge clk_1p5m_w or negedge sys_rst) begin
        if (!sys_rst)
            audio_frame_cnt <= 5'd0;
        else
            audio_frame_cnt <= audio_frame_cnt + 1'b1;
    end

    wire evt_valid;
    wire [4:0] evt_voice;
    wire [6:0] evt_note;
    wire evt_on;
    wire [6:0] evt_vel;
    wire [1:0] evt_timbre;
    wire [7:0] bend_sync;
    wire [7:0] vibrato_sync;

    a_b_adapter u_adapter (
        .clk         (sys_clk),
        .rst_n       (sys_rst),
        .note_id     (note_id),
        .velocity    (velocity),
        .note_on     (note_on),
        .note_off    (note_off),
        .voice_id    (voice_id),
        .pitch_bend  (pitch_bend),
        .vibrato     (vibrato),
        .timbre_sel  (2'd0),
        .all_off     (1'b0),
        .evt_valid   (evt_valid),
        .evt_voice   (evt_voice),
        .evt_note    (evt_note),
        .evt_on      (evt_on),
        .evt_vel     (evt_vel),
        .evt_timbre  (evt_timbre),
        .pitch_bend_o(bend_sync),
        .vibrato_o   (vibrato_sync)
    );

    wire signed [15:0] synth_audio;
    wire signed [15:0] synth_audio_fx;

    synth_evt #(.N(32)) u_synth (
        .wr_clk    (sys_clk),
        .clk       (clk_1p5m_w),
        .rst_n     (sys_rst),
        .tick      (audio_tick),
        .test_mode (1'b0),          // normal four-key performance build
        .pitch_bend(bend_sync),
        .vibrato   (vibrato_sync),
        .evt_valid (evt_valid),
        .evt_voice (evt_voice),
        .evt_note  (evt_note),
        .evt_on    (evt_on),
        .evt_vel   (evt_vel),
        .evt_timbre(evt_timbre),
        .all_off   (1'b0),
        .audio     (synth_audio)
    );

    fx_chain_full u_fx (
        .clk   (clk_1p5m_w),
        .rst_n (sys_rst),
        .tick  (audio_tick),
        .din   (synth_audio),
        .mode  (fx_mode),
        .dout  (synth_audio_fx)
    );

    // Mode 0 must be the exact verified dry path from build 62.
    wire signed [15:0] selected_audio =
        (fx_mode == 2'd0) ? synth_audio : synth_audio_fx;

    // Register the selected input once before the known-good I2S driver.
    reg signed [15:0] audio_out;
    always @(posedge clk_1p5m_w or negedge sys_rst) begin
        if (!sys_rst)
            audio_out <= 16'sd0;
        else
            audio_out <= selected_audio;
    end

    wire req_w;
    audio_drive u_i2s (
        .clk_1p536m(clk_1p5m_w),
        .rst_n     (sys_rst),
        .idata     (audio_out),
        .req       (req_w),
        .HP_BCK    (HP_BCK),
        .HP_WS     (HP_WS),
        .HP_DIN    (HP_DIN)
    );

    assign PA_EN = 1'b0;

endmodule
