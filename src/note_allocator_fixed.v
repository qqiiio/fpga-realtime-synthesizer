// A-side note allocator with deterministic multi-key event serialization.
//
// The original module scanned four keys in one clock but exposed only one
// output event, so simultaneous chord presses were overwritten. This version
// accepts all simultaneous edges into a 4-bit pending FIFO and emits one
// legal one-cycle event per 50 MHz clock.
module note_allocator (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [3:0]  key_press,
    input  wire [3:0]  key_release,

    input  wire [7:0]  pitch_bend_in,
    input  wire [7:0]  vibrato_in,

    output reg  [7:0]  note_id,
    output reg  [7:0]  velocity,
    output reg         note_on,
    output reg         note_off,
    output reg  [4:0]  voice_id,
    output reg  [7:0]  pitch_bend,
    output reg  [7:0]  vibrato
);

    localparam [7:0] NOTE_K1 = 8'd60;
    localparam [7:0] NOTE_K2 = 8'd64;
    localparam [7:0] NOTE_K3 = 8'd67;
    localparam [7:0] NOTE_K4 = 8'd72;
    localparam [7:0] FIXED_VEL = 8'd100;

    reg [31:0] voice_busy;
    reg [4:0]  key_voice_map [0:3];
    reg [3:0]  key_active;

    // Pending edge queues absorb four simultaneous key edges.
    reg [3:0] pending_press;
    reg [3:0] pending_release;

    integer i;
    integer k;
    reg found;
    reg [4:0] free_voice;
    reg [1:0] event_idx;
    reg [7:0] event_note;

    function [1:0] lowest_index;
        input [3:0] bits;
        begin
            casez (bits)
                4'b???1: lowest_index = 2'd0;
                4'b??10: lowest_index = 2'd1;
                4'b?100: lowest_index = 2'd2;
                default: lowest_index = 2'd3;
            endcase
        end
    endfunction

    function [7:0] note_for_key;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: note_for_key = NOTE_K1;
                2'd1: note_for_key = NOTE_K2;
                2'd2: note_for_key = NOTE_K3;
                default: note_for_key = NOTE_K4;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_id       <= 8'd0;
            velocity      <= 8'd0;
            note_on       <= 1'b0;
            note_off      <= 1'b0;
            voice_id      <= 5'd0;
            pitch_bend    <= 8'd64;
            vibrato       <= 8'd0;
            voice_busy    <= 32'd0;
            key_active    <= 4'd0;
            pending_press <= 4'd0;
            pending_release <= 4'd0;
            for (i = 0; i < 4; i = i + 1)
                key_voice_map[i] <= 5'd0;
        end
        else begin
            note_on  <= 1'b0;
            note_off <= 1'b0;
            pitch_bend <= pitch_bend_in;
            vibrato    <= vibrato_in;

            // Edge pulses may be one cycle only. Accumulate them before
            // consuming one event from the queue.
            pending_press   <= pending_press | key_press;
            pending_release <= pending_release | key_release;

            if (pending_release != 4'd0) begin
                // Release has priority, preventing a stale voice from
                // being reallocated in the same cycle.
                event_idx = lowest_index(pending_release);
                pending_release[event_idx] <= 1'b0;

                if (key_active[event_idx]) begin
                    voice_id <= key_voice_map[event_idx];
                    note_id  <= note_for_key(event_idx);
                    velocity <= FIXED_VEL;
                    note_off <= 1'b1;
                    voice_busy[key_voice_map[event_idx]] <= 1'b0;
                    key_active[event_idx] <= 1'b0;
                end
            end
            else if (pending_press != 4'd0) begin
                event_idx = lowest_index(pending_press);
                pending_press[event_idx] <= 1'b0;

                if (!key_active[event_idx]) begin
                    found = 1'b0;
                    free_voice = 5'd0;
                    for (k = 0; k < 32; k = k + 1) begin
                        if (!voice_busy[k] && !found) begin
                            free_voice = k[4:0];
                            found = 1'b1;
                        end
                    end

                    if (found) begin
                        voice_busy[free_voice] <= 1'b1;
                        key_voice_map[event_idx] <= free_voice;
                        key_active[event_idx] <= 1'b1;

                        voice_id <= free_voice;
                        note_id  <= note_for_key(event_idx);
                        velocity <= FIXED_VEL;
                        note_on  <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
