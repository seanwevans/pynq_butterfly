`timescale 1ns/1ps

module ntt16_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic [31:0] q,

    /*
     * Host-side memory loading interface.
     *
     * Loading is accepted only while the controller is idle.
     */
    input  logic        load_we,
    input  logic [3:0]  load_addr,
    input  logic [31:0] load_data,

    /*
     * Host-side asynchronous read interface.
     */
    input  logic [3:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    /*
     * Pulses after the final butterfly of each stage.
     */
    output logic        stage_done,
    output logic [1:0]  stage_completed
);

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_LAUNCH,
        STATE_WAIT_RESULT
    } state_t;

    state_t state;

    /*
     * Sixteen 32-bit coefficient locations.
     *
     * This is deliberately modeled as an array so the same controller
     * can later be placed around a dual-port BRAM.
     */
    logic [31:0] memory [0:15];

    logic [31:0] q_hold;

    logic [1:0] stage;
    logic [2:0] butterfly;

    logic [3:0] index_a;
    logic [3:0] index_b;

    logic [31:0] twiddle;

    logic        butterfly_start;
    logic        butterfly_busy;
    logic        butterfly_done;

    logic [31:0] butterfly_out_a;
    logic [31:0] butterfly_out_b;

    assign read_data = memory[read_addr];

    /*
     * Butterfly address schedule:
     *
     * stage 0: (0,1), (2,3), ..., (14,15)
     * stage 1: (0,2), (1,3), ..., (13,15)
     * stage 2: (0,4), (1,5), ..., (11,15)
     * stage 3: (0,8), (1,9), ..., (7,15)
     */
    always @*
    begin
        index_a = 4'd0;
        index_b = 4'd0;

        case (stage)
            2'd0:
            begin
                index_a = {butterfly, 1'b0};
                index_b = {butterfly, 1'b0} + 4'd1;
            end

            2'd1:
            begin
                index_a =
                    {butterfly[2:1], 2'b00} +
                    {3'b000, butterfly[0]};

                index_b = index_a + 4'd2;
            end

            2'd2:
            begin
                index_a =
                    {butterfly[2], 3'b000} +
                    {2'b00, butterfly[1:0]};

                index_b = index_a + 4'd4;
            end

            2'd3:
            begin
                index_a = {1'b0, butterfly};
                index_b = {1'b1, butterfly};
            end

            default:
            begin
                index_a = 4'd0;
                index_b = 4'd0;
            end
        endcase
    end

    /*
     * Exact twiddle schedule generated from:
     *
     * OpenFHE tower 0
     * q     = 1073692673
     * psi   = 763394433
     * omega = 1051583792
     */
    function automatic logic [31:0] twiddle_for(
        input logic [1:0] stage_value,
        input logic [2:0] butterfly_value
    );
        begin
            twiddle_for = 32'd1;

            case (stage_value)
                2'd0:
                begin
                    twiddle_for = 32'd1;
                end

                2'd1:
                begin
                    case (butterfly_value[0])
                        1'b0:
                            twiddle_for = 32'd1;

                        1'b1:
                            twiddle_for = 32'd8388480;
                    endcase
                end

                2'd2:
                begin
                    case (butterfly_value[1:0])
                        2'd0:
                            twiddle_for = 32'd1;

                        2'd1:
                            twiddle_for = 32'd808610892;

                        2'd2:
                            twiddle_for = 32'd8388480;

                        2'd3:
                            twiddle_for = 32'd412890215;
                    endcase
                end

                2'd3:
                begin
                    case (butterfly_value)
                        3'd0:
                            twiddle_for = 32'd1;

                        3'd1:
                            twiddle_for = 32'd1051583792;

                        3'd2:
                            twiddle_for = 32'd808610892;

                        3'd3:
                            twiddle_for = 32'd286011093;

                        3'd4:
                            twiddle_for = 32'd8388480;

                        3'd5:
                            twiddle_for = 32'd103009083;

                        3'd6:
                            twiddle_for = 32'd412890215;

                        3'd7:
                            twiddle_for = 32'd918502623;
                    endcase
                end

                default:
                begin
                    twiddle_for = 32'd1;
                end
            endcase
        end
    endfunction

    assign twiddle =
        twiddle_for(stage, butterfly);

    /*
     * STATE_LAUNCH lasts one clock, producing one start pulse.
     */
    assign butterfly_start =
        state == STATE_LAUNCH;

    butterfly_core butterfly_unit (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (butterfly_start),

        .a       (memory[index_a]),
        .b       (memory[index_b]),
        .omega   (twiddle),
        .q       (q_hold),

        .out_a   (butterfly_out_a),
        .out_b   (butterfly_out_b),
        .busy    (butterfly_busy),
        .done    (butterfly_done)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;

            q_hold <= 32'd0;

            stage     <= 2'd0;
            butterfly <= 3'd0;

            busy <= 1'b0;
            done <= 1'b0;

            stage_done      <= 1'b0;
            stage_completed <= 2'd0;
        end
        else
        begin
            done       <= 1'b0;
            stage_done <= 1'b0;

            /*
             * External writes are permitted only while idle.
             */
            if (load_we && !busy)
            begin
                memory[load_addr] <= load_data;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start && !busy)
                    begin
                        q_hold <= q;

                        stage     <= 2'd0;
                        butterfly <= 3'd0;

                        busy <= 1'b1;

                        state <= STATE_LAUNCH;
                    end
                end

                STATE_LAUNCH:
                begin
                    /*
                     * butterfly_start is high during this state.
                     * The butterfly samples its inputs at this edge.
                     */
                    state <= STATE_WAIT_RESULT;
                end

                STATE_WAIT_RESULT:
                begin
                    if (butterfly_done)
                    begin
                        memory[index_a] <= butterfly_out_a;
                        memory[index_b] <= butterfly_out_b;

                        if (butterfly == 3'd7)
                        begin
                            stage_done      <= 1'b1;
                            stage_completed <= stage;

                            if (stage == 2'd3)
                            begin
                                busy <= 1'b0;
                                done <= 1'b1;

                                state <= STATE_IDLE;
                            end
                            else
                            begin
                                stage     <= stage + 1'b1;
                                butterfly <= 3'd0;

                                state <= STATE_LAUNCH;
                            end
                        end
                        else
                        begin
                            butterfly <= butterfly + 1'b1;

                            state <= STATE_LAUNCH;
                        end
                    end
                end

                default:
                begin
                    state <= STATE_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
