// ADSR with an explicit retrigger pulse for sequencer note events.
// envelope range: 0..65535, updated once per audio sample tick.
module adsr_event (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick,
    input  wire        trigger,
    input  wire        gate,
    output reg  [15:0] env
);

    localparam [15:0] ATTACK_STEP   = 16'd47;
    localparam [15:0] DECAY_STEP    = 16'd4;
    localparam [15:0] SUSTAIN_LEVEL = 16'd32768;
    localparam [15:0] RELEASE_STEP  = 16'd3;

    localparam [2:0] S_IDLE    = 3'd0;
    localparam [2:0] S_ATTACK  = 3'd1;
    localparam [2:0] S_DECAY   = 3'd2;
    localparam [2:0] S_SUSTAIN = 3'd3;
    localparam [2:0] S_RELEASE = 3'd4;

    reg [2:0] state;
    reg       gate_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            env    <= 16'd0;
            gate_d <= 1'b0;
        end
        else if (tick) begin
            gate_d <= gate;

            if (trigger) begin
                state <= S_ATTACK;
            end
            else begin
                case (state)
                    S_IDLE: begin
                        env <= 16'd0;
                        if (gate & ~gate_d)
                            state <= S_ATTACK;
                    end

                    S_ATTACK: begin
                        if (!gate) begin
                            state <= S_RELEASE;
                        end
                        else if (env >= (16'd65535 - ATTACK_STEP)) begin
                            env   <= 16'd65535;
                            state <= S_DECAY;
                        end
                        else begin
                            env <= env + ATTACK_STEP;
                        end
                    end

                    S_DECAY: begin
                        if (!gate) begin
                            state <= S_RELEASE;
                        end
                        else if (env <= (SUSTAIN_LEVEL + DECAY_STEP)) begin
                            env   <= SUSTAIN_LEVEL;
                            state <= S_SUSTAIN;
                        end
                        else begin
                            env <= env - DECAY_STEP;
                        end
                    end

                    S_SUSTAIN: begin
                        env <= SUSTAIN_LEVEL;
                        if (!gate)
                            state <= S_RELEASE;
                    end

                    S_RELEASE: begin
                        if (gate & ~gate_d)
                            state <= S_ATTACK;
                        else if (env <= RELEASE_STEP) begin
                            env   <= 16'd0;
                            state <= S_IDLE;
                        end
                        else begin
                            env <= env - RELEASE_STEP;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
