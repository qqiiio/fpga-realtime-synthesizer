// Compatibility adapter for A's fixed interface:
// note_id[7:0], velocity[7:0], note_on, note_off, voice_id[4:0],
// pitch_bend[7:0], vibrato[7:0].
//
// The current B engine consumes one unified event. Pitch bend and vibrato
// are passed through for later modulation support; with A's defaults
// (pitch_bend=64, vibrato=0) they have no effect.
module a_b_adapter (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  note_id,
    input  wire [7:0]  velocity,
    input  wire        note_on,
    input  wire        note_off,
    input  wire [4:0]  voice_id,
    input  wire [7:0]  pitch_bend,
    input  wire [7:0]  vibrato,

    input  wire [1:0]  timbre_sel,
    input  wire        all_off,

    output wire        evt_valid,
    output wire [4:0]  evt_voice,
    output wire [6:0]  evt_note,
    output wire        evt_on,
    output wire [6:0]  evt_vel,
    output wire [1:0]  evt_timbre,
    output wire [7:0]  pitch_bend_o,
    output wire [7:0]  vibrato_o
);

    // A promises one-cycle pulses. note_off wins if both somehow pulse
    // together, preventing a stuck note.
    assign evt_valid  = ((note_on | note_off) && !note_id[7]);
    assign evt_voice  = voice_id;
    assign evt_note   = note_id[6:0];
    assign evt_on     = note_on & ~note_off;
    assign evt_vel    = velocity[6:0];
    assign evt_timbre = timbre_sel;
    assign pitch_bend_o = pitch_bend;
    assign vibrato_o    = vibrato;

endmodule
