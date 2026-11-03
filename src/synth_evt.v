// Event-driven 32-voice synthesis engine.
// A supplies one-cycle events in wr_clk (50 MHz). A 32-entry asynchronous
// FIFO transfers them into the 1.5 MHz audio clock domain.
module synth_evt #(
    parameter N = 32,
    parameter FILL_ONLY = 0
)(
    input  wire               wr_clk,
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick,
    input  wire               test_mode,
    input  wire        [7:0]  pitch_bend,
    input  wire        [7:0]  vibrato,

    input  wire               evt_valid,
    input  wire        [4:0]  evt_voice,
    input  wire        [6:0]  evt_note,
    input  wire               evt_on,
    input  wire        [6:0]  evt_vel,
    input  wire        [1:0]  evt_timbre,
    input  wire               all_off,

    output reg  signed [15:0] audio
);

    localparam integer VW = 5;
    localparam integer EVENT_W = 22;

    function [5:0] bin2gray;
        input [5:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    //------------------------------------------------------------------
    // A-domain to B-domain event FIFO, depth 32.
    //------------------------------------------------------------------
    reg [EVENT_W-1:0] evt_mem [0:31];
    reg [5:0] wbin, wgray, rbin, rgray;
    reg [5:0] wgray_s1, wgray_s2, rgray_s1, rgray_s2;
    wire [5:0] wbin_next  = wbin + 1'b1;
    wire [5:0] wgray_next = bin2gray(wbin_next);
    wire [5:0] rbin_next  = rbin + 1'b1;
    wire [5:0] rgray_next = bin2gray(rbin_next);
    wire       wr_full =
        (wgray_next == {~rgray_s2[5:4], rgray_s2[3:0]});
    wire       rd_empty = (rgray == wgray_s2);

    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wbin      <= 6'd0;
            wgray     <= 6'd0;
            rgray_s1  <= 6'd0;
            rgray_s2  <= 6'd0;
        end
        else begin
            rgray_s1 <= rgray;
            rgray_s2 <= rgray_s1;
            if (evt_valid && !wr_full) begin
                evt_mem[wbin[4:0]] <= {
                    evt_timbre, evt_vel, evt_on, evt_note, evt_voice
                };
                wbin  <= wbin_next;
                wgray <= wgray_next;
            end
        end
    end

    reg [EVENT_W-1:0] fifo_rdata;
    reg               rd_fire;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rbin      <= 6'd0;
            rgray     <= 6'd0;
            wgray_s1  <= 6'd0;
            wgray_s2  <= 6'd0;
            fifo_rdata <= {EVENT_W{1'b0}};
            rd_fire    <= 1'b0;
        end
        else begin
            wgray_s1 <= wgray;
            wgray_s2 <= wgray_s1;
            rd_fire  <= ~rd_empty;
            if (!rd_empty) begin
                fifo_rdata <= evt_mem[rbin[4:0]];
                rbin       <= rbin_next;
                rgray      <= rgray_next;
            end
        end
    end

    // all_off is a toggle synchronized into the audio clock domain.
    reg alloff_wr, alloff_s1, alloff_s2, alloff_s3;
    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n)
            alloff_wr <= 1'b0;
        else if (all_off)
            alloff_wr <= ~alloff_wr;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alloff_s1 <= 1'b0;
            alloff_s2 <= 1'b0;
            alloff_s3 <= 1'b0;
        end
        else begin
            alloff_s1 <= alloff_wr;
            alloff_s2 <= alloff_s1;
            alloff_s3 <= alloff_s2;
        end
    end
    wire alloff_pulse = alloff_s2 ^ alloff_s3;

    //------------------------------------------------------------------
    // MIDI note -> 32-bit frequency control word.
    // fcw = round(f_note * 2^32 / 46875).
    //------------------------------------------------------------------
    function [31:0] midi_fcw;
        input [6:0] note;
        integer oct;
        reg [3:0] pc;
        reg [31:0] base;
        begin
            pc = note % 12;
            case (pc)
                4'd0:  base = 32'd23971696; // C4
                4'd1:  base = 32'd25395299; // C#4
                4'd2:  base = 32'd26907319; // D4
                4'd3:  base = 32'd28510180; // D#4
                4'd4:  base = 32'd30202444; // E4
                4'd5:  base = 32'd31998375; // F4
                4'd6:  base = 32'd33901020; // F#4
                4'd7:  base = 32'd35916962; // G4
                4'd8:  base = 32'd38052531; // G#4
                4'd9:  base = 32'd40315426; // A4
               4'd10:  base = 32'd42713506; // A#4
               default:base = 32'd45252536; // B4
            endcase

            midi_fcw = base;
            if (note >= 7'd60) begin
                oct = (note - 7'd60) / 12;
                midi_fcw = base << oct;
            end
            else begin
                oct = (7'd60 - note) / 12;
                midi_fcw = base >> oct;
            end
        end
    endfunction

    // Pitch-bend approximation with no DSP:
    // one bend step is base_fcw / 512, about 3.4 cents.
    // bend=64 is center; range is approximately +/-2.1 semitones.
    function [31:0] apply_pitch_bend;
        input [31:0] base;
        input [7:0]  bend;
        integer bi;
        reg [7:0] magnitude;
        reg [38:0] step;
        reg [38:0] sum;
        begin
            magnitude = (bend >= 8'd64) ? (bend - 8'd64) : (8'd64 - bend);
            step = {7'd0, base} >> 9;
            sum  = 39'd0;
            for (bi = 0; bi < 7; bi = bi + 1)
                if (magnitude[bi])
                    sum = sum + (step << bi);

            if (bend >= 8'd64)
                apply_pitch_bend = base + sum[31:0];
            else
                apply_pitch_bend = base - sum[31:0];
        end
    endfunction

    // Test mode uses 32 widely spaced MIDI notes (C4 through F8) so a
    // phone spectrum display can resolve all expected peaks.
    function [6:0] test_note_of;
        input [5:0] idx;
        begin
            case (idx)
                6'd0:  test_note_of = 7'd60;  // C4
                6'd1:  test_note_of = 7'd62;  // D4
                6'd2:  test_note_of = 7'd64;  // E4
                6'd3:  test_note_of = 7'd65;  // F4
                6'd4:  test_note_of = 7'd67;  // G4
                6'd5:  test_note_of = 7'd69;  // A4
                6'd6:  test_note_of = 7'd71;  // B4
                6'd7:  test_note_of = 7'd72;  // C5
                6'd8:  test_note_of = 7'd74;  // D5
                6'd9:  test_note_of = 7'd76;  // E5
               6'd10:  test_note_of = 7'd77;  // F5
               6'd11:  test_note_of = 7'd79;  // G5
               6'd12:  test_note_of = 7'd81;  // A5
               6'd13:  test_note_of = 7'd83;  // B5
               6'd14:  test_note_of = 7'd84;  // C6
               6'd15:  test_note_of = 7'd86;  // D6
               6'd16:  test_note_of = 7'd88;  // E6
               6'd17:  test_note_of = 7'd89;  // F6
               6'd18:  test_note_of = 7'd91;  // G6
               6'd19:  test_note_of = 7'd93;  // A6
               6'd20:  test_note_of = 7'd95;  // B6
               6'd21:  test_note_of = 7'd96;  // C7
               6'd22:  test_note_of = 7'd98;  // D7
               6'd23:  test_note_of = 7'd100; // E7
               6'd24:  test_note_of = 7'd101; // F7
               6'd25:  test_note_of = 7'd103; // G7
               6'd26:  test_note_of = 7'd105; // A7
               6'd27:  test_note_of = 7'd107; // B7
               6'd28:  test_note_of = 7'd108; // C8
               6'd29:  test_note_of = 7'd110; // D8
               6'd30:  test_note_of = 7'd112; // E8
               default:test_note_of = 7'd113; // F8
            endcase
        end
    endfunction

    //------------------------------------------------------------------
    // Per-voice control state.
    //------------------------------------------------------------------
    reg [31:0] base_fcw_a [0:N-1];
    reg [31:0] fcw_a     [0:N-1];
    reg [1:0]  timbre_a  [0:N-1];
    reg [6:0]  vel_a     [0:N-1];
    reg        gate_a    [0:N-1];
    reg        trig_a    [0:N-1];

    reg [7:0] bend_s1, bend_s2, bend_target;
    reg [7:0] vibrato_s1, vibrato_s2;
    reg [5:0] bend_update_idx;
    reg       bend_updating;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bend_s1    <= 8'd64;
            bend_s2    <= 8'd64;
            vibrato_s1 <= 8'd0;
            vibrato_s2 <= 8'd0;
        end
        else begin
            bend_s1    <= pitch_bend;
            bend_s2    <= bend_s1;
            vibrato_s1 <= vibrato;
            vibrato_s2 <= vibrato_s1;
        end
    end

    wire        q_on     = fifo_rdata[12];
    wire [6:0]  q_note   = fifo_rdata[11:5];
    wire [4:0]  q_voice  = fifo_rdata[4:0];
    wire [6:0]  q_vel    = fifo_rdata[19:13];
    wire [1:0]  q_timbre = fifo_rdata[21:20];
    wire        note_ok  = (q_note >= 7'd24) && (q_note <= 7'd108);

    integer vi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (vi = 0; vi < N; vi = vi + 1) begin
                base_fcw_a[vi] <= 32'd0;
                fcw_a[vi]    <= 32'd0;
                timbre_a[vi] <= 2'd0;
                vel_a[vi]    <= 7'd0;
                gate_a[vi]   <= 1'b0;
                trig_a[vi]   <= 1'b0;
            end
            bend_target <= 8'd64;
            bend_update_idx <= 6'd0;
            bend_updating <= 1'b0;
        end
        else begin
            for (vi = 0; vi < N; vi = vi + 1)
                trig_a[vi] <= 1'b0;

            if (alloff_pulse) begin
                for (vi = 0; vi < N; vi = vi + 1)
                    gate_a[vi] <= 1'b0;
            end

            // Apply a changed bend value to all voices, one voice per
            // audio clock. Thirty-two voices finish in about 21 us.
            if (bend_s2 != bend_target) begin
                bend_target <= bend_s2;
                bend_update_idx <= 6'd0;
                bend_updating <= 1'b1;
            end

            if (bend_updating) begin
                fcw_a[bend_update_idx[4:0]] <=
                    apply_pitch_bend(base_fcw_a[bend_update_idx[4:0]], bend_s2);
                if (bend_update_idx == (N-1))
                    bend_updating <= 1'b0;
                else
                    bend_update_idx <= bend_update_idx + 1'b1;
            end

            if (rd_fire && !test_mode) begin
                if (q_voice < N && note_ok) begin
                    if (q_on) begin
                        base_fcw_a[q_voice] <= midi_fcw(q_note);
                        fcw_a[q_voice]    <=
                            apply_pitch_bend(midi_fcw(q_note), bend_s2);
                        timbre_a[q_voice] <= q_timbre;
                        vel_a[q_voice]    <= q_vel;
                        gate_a[q_voice]   <= 1'b1;
                        trig_a[q_voice]   <= 1'b1;
                    end
                    else begin
                        gate_a[q_voice] <= 1'b0;
                    end
                end
            end
        end
    end

    //------------------------------------------------------------------
    // 32 parallel voices.
    //------------------------------------------------------------------
    reg test_mode_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            test_mode_d <= 1'b0;
        else
            test_mode_d <= test_mode;
    end
    wire test_trig = test_mode & ~test_mode_d;

    wire signed [15:0] voice_out [0:N-1];
    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_voice
            wire [6:0]  test_note = test_note_of(gi[5:0]);
            wire [31:0] use_fcw =
                test_mode ? midi_fcw(test_note) : fcw_a[gi];
            wire [1:0] use_timbre =
                test_mode ? 2'd0 : timbre_a[gi];
            wire [6:0] use_vel =
                test_mode ? 7'd127 : vel_a[gi];
            wire use_gate = test_mode ? 1'b1 : gate_a[gi];
            wire use_trig = test_mode ? test_trig : trig_a[gi];

            voice_lut u_voice (
                .clk      (clk),
                .rst_n    (rst_n),
                .tick     (tick),
                .fcw      (use_fcw),
                .timbre   (use_timbre),
                .velocity (use_vel),
                .trigger  (use_trig),
                .gate     (use_gate),
                .out      (voice_out[gi])
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // Pipelined balanced mixer. The original 32-stage combinational
    // ripple sum was unreliable after place-and-route on the 32-voice
    // design. Register every tree level, then apply gain at the end.
    //------------------------------------------------------------------
    wire signed [20:0] voice_ext [0:31];
    generate
        for (gi = 0; gi < 32; gi = gi + 1)
            assign voice_ext[gi] =
                {{5{voice_out[gi][15]}}, voice_out[gi]};
    endgenerate

    wire signed [20:0] pair_comb [0:15];
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_pair
            assign pair_comb[gi] =
                voice_ext[2*gi] + voice_ext[2*gi + 1];
        end
    endgenerate

    reg signed [20:0] pair_r [0:15];
    reg signed [20:0] quad_r [0:7];
    reg signed [20:0] oct_r  [0:3];
    reg signed [20:0] half_r [0:1];
    integer mix_i;

    wire signed [20:0] mix_sum = half_r[0] + half_r[1];
    wire signed [20:0] mix_scaled =
        mix_sum >>> (test_mode ? 5 : 2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (mix_i = 0; mix_i < 16; mix_i = mix_i + 1)
                pair_r[mix_i] <= 21'sd0;
            for (mix_i = 0; mix_i < 8; mix_i = mix_i + 1)
                quad_r[mix_i] <= 21'sd0;
            for (mix_i = 0; mix_i < 4; mix_i = mix_i + 1)
                oct_r[mix_i] <= 21'sd0;
            half_r[0] <= 21'sd0;
            half_r[1] <= 21'sd0;
            audio     <= 16'sd0;
        end
        else begin
            for (mix_i = 0; mix_i < 16; mix_i = mix_i + 1)
                pair_r[mix_i] <= pair_comb[mix_i];
            for (mix_i = 0; mix_i < 8; mix_i = mix_i + 1)
                quad_r[mix_i] <= pair_r[2*mix_i] + pair_r[2*mix_i + 1];
            for (mix_i = 0; mix_i < 4; mix_i = mix_i + 1)
                oct_r[mix_i] <= quad_r[2*mix_i] + quad_r[2*mix_i + 1];
            half_r[0] <= oct_r[0] + oct_r[1];
            half_r[1] <= oct_r[2] + oct_r[3];
            audio     <= mix_scaled[15:0];
        end
    end

endmodule
