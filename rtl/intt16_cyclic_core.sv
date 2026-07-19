`timescale 1ns/1ps

/*
 * N=16 inverse cyclic NTT controller.
 *
 * The input must already be stored in bit-reversed order.
 * The output is produced in natural order.
 *
 * OpenFHE-derived profile:
 *
 * q             = 1073692673
 * omega_inverse = 155190050
 */
module intt16_cyclic_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic [31:0] q,

    input  logic        load_we,
    input  logic [3:0]  load_addr,
    input  logic [31:0] load_data,

    input  logic [3:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic        stage_done,
    output logic [1:0]  stage_completed
);

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_LAUNCH,
        STATE_WAIT_RESULT
    } state_t;

    state_t state;

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
     * Address schedule for radix-2 DIT:
     *
     * stage 0: distance 1
     * stage 1: distance 2
     * stage 2: distance 4
     * stage 3: distance 8
     */
    always @*
    begin
        index_a = 4'd0;
        index_b = 4'd0;

        case (stage)
            2'd0:
            begin
                index_a = {butterfly, 1'b0};
                index_b = index_a + 4'd1;
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
     * Inverse twiddle schedule generated using:
     *
     * omega_inverse = 155190050
     */
    function automatic logic [31:0] inverse_twiddle_for(
        input logic [1:0] stage_value,
        input logic [2:0] butterfly_value
    );
        begin
            inverse_twiddle_for = 32'd1;

            case (stage_value)
                2'd0:
                begin
                    inverse_twiddle_for = 32'd1;
                end

                2'd1:
                begin
                    case (butterfly_value[0])
                        1'b0:
                            inverse_twiddle_for = 32'd1;

                        1'b1:
                            inverse_twiddle_for = 32'd1065304193;
                    endcase
                end

                2'd2:
                begin
                    case (butterfly_value[1:0])
                        2'd0:
                            inverse_twiddle_for = 32'd1;

                        2'd1:
                            inverse_twiddle_for = 32'd660802458;

                        2'd2:
                            inverse_twiddle_for = 32'd1065304193;

                        2'd3:
                            inverse_twiddle_for = 32'd265081781;
                    endcase
                end

                2'd3:
                begin
                    case (butterfly_value)
                        3'd0:
                            inverse_twiddle_for = 32'd1;

                        3'd1:
                            inverse_twiddle_for = 32'd155190050;

                        3'd2:
                            inverse_twiddle_for = 32'd660802458;

                        3'd3:
                            inverse_twiddle_for = 32'd970683590;

                        3'd4:
                            inverse_twiddle_for = 32'd1065304193;

                        3'd5:
                            inverse_twiddle_for = 32'd787681580;

                        3'd6:
                            inverse_twiddle_for = 32'd265081781;

                        3'd7:
                            inverse_twiddle_for = 32'd22108881;
                    endcase
                end

                default:
                begin
                    inverse_twiddle_for = 32'd1;
                end
            endcase
        end
    endfunction

    assign twiddle =
        inverse_twiddle_for(stage, butterfly);

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

            stage      <= 2'd0;
            butterfly  <= 3'd0;

            busy <= 1'b0;
            done <= 1'b0;

            stage_done      <= 1'b0;
            stage_completed <= 2'd0;
        end
        else
        begin
            done       <= 1'b0;
            stage_done <= 1'b0;

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

                        stage      <= 2'd0;
                        butterfly  <= 3'd0;

                        busy <= 1'b1;

                        state <= STATE_LAUNCH;
                    end
                end

                STATE_LAUNCH:
                begin
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
                                stage      <= stage + 1'b1;
                                butterfly  <= 3'd0;

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
