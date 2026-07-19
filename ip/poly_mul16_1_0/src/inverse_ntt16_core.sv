`timescale 1ns/1ps

/*
 * Complete N=16 inverse negacyclic NTT.
 *
 * Input:
 *     natural-order forward-transform coefficients
 *
 * Step 1:
 *     place the input into bit-reversed memory order
 *
 * Step 2:
 *     execute the inverse cyclic NTT using omega_inverse
 *
 * Step 3:
 *     output[j] =
 *         cyclic_output[j]
 *         * N_inverse
 *         * psi_inverse^j
 *         mod q
 */
module inverse_ntt16_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic        load_we,
    input  logic [3:0]  load_addr,
    input  logic [31:0] load_data,

    input  logic [3:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done
);

    localparam logic [31:0] PROFILE_Q =
        32'd1073692673;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_BIT_REVERSE,
        STATE_INTT_LAUNCH,
        STATE_INTT_WAIT,
        STATE_SCALE_LAUNCH,
        STATE_SCALE_WAIT,
        STATE_SCALE_WRITE
    } state_t;

    state_t state;

    logic [31:0] input_memory  [0:15];
    logic [31:0] output_memory [0:15];

    logic [3:0] copy_index;
    logic [3:0] scale_index;

    logic        intt_start;

    logic        intt_load_we;
    logic [3:0]  intt_load_addr;
    logic [31:0] intt_load_data;

    logic [3:0]  intt_read_addr;
    logic [31:0] intt_read_data;

    logic        intt_busy;
    logic        intt_done;
    logic        intt_stage_done;
    logic [1:0]  intt_stage_completed;

    logic [31:0] scale_factor;

    logic        scale_start;
    logic [31:0] scale_result;
    logic        scale_busy;
    logic        scale_done;

    assign read_data =
        output_memory[read_addr];

    function automatic logic [3:0] bit_reverse4(
        input logic [3:0] value
    );
        begin
            bit_reverse4 = {
                value[0],
                value[1],
                value[2],
                value[3]
            };
        end
    endfunction

    /*
     * N_inverse * psi_inverse^j mod q.
     *
     * N_inverse   = 1006586881
     * psi_inverse = 751566494
     */
    function automatic logic [31:0] scale_for(
        input logic [3:0] index
    );
        begin
            case (index)
                4'd0:
                    scale_for = 32'd1006586881;

                4'd1:
                    scale_for = 32'd181184490;

                4'd2:
                    scale_for = 32'd949180467;

                4'd3:
                    scale_for = 32'd993128858;

                4'd4:
                    scale_for = 32'd443934906;

                4'd5:
                    scale_for = 32'd969199609;

                4'd6:
                    scale_for = 32'd731725645;

                4'd7:
                    scale_for = 32'd468532259;

                4'd8:
                    scale_for = 32'd1073168393;

                4'd9:
                    scale_for = 32'd1045204604;

                4'd10:
                    scale_for = 32'd317653267;

                4'd11:
                    scale_for = 32'd13840848;

                4'd12:
                    scale_for = 32'd754731324;

                4'd13:
                    scale_for = 32'd1047889672;

                4'd14:
                    scale_for = 32'd1007968686;

                4'd15:
                    scale_for = 32'd19393640;

                default:
                    scale_for = 32'd1;
            endcase
        end
    endfunction

    /*
     * Copy ordinary transform input into bit-reversed INTT memory.
     */
    assign intt_load_we =
        state == STATE_BIT_REVERSE;

    assign intt_load_addr =
        bit_reverse4(copy_index);

    assign intt_load_data =
        input_memory[copy_index];

    assign intt_start =
        state == STATE_INTT_LAUNCH;

    assign intt_read_addr =
        scale_index;

    intt16_cyclic_core inverse_cyclic_ntt (
        .clk             (clk),
        .reset_n         (reset_n),
        .start           (intt_start),

        .q               (PROFILE_Q),

        .load_we         (intt_load_we),
        .load_addr       (intt_load_addr),
        .load_data       (intt_load_data),

        .read_addr       (intt_read_addr),
        .read_data       (intt_read_data),

        .busy            (intt_busy),
        .done            (intt_done),

        .stage_done      (intt_stage_done),
        .stage_completed (intt_stage_completed)
    );

    assign scale_factor =
        scale_for(scale_index);

    assign scale_start =
        state == STATE_SCALE_LAUNCH;

    modmul_core scale_multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scale_start),

        .a       (scale_factor),
        .b       (intt_read_data),
        .q       (PROFILE_Q),

        .result  (scale_result),
        .busy    (scale_busy),
        .done    (scale_done)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;

            copy_index  <= 4'd0;
            scale_index <= 4'd0;

            busy <= 1'b0;
            done <= 1'b0;
        end
        else
        begin
            done <= 1'b0;

            if (load_we && !busy)
            begin
                input_memory[load_addr] <= load_data;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start && !busy)
                    begin
                        copy_index <= 4'd0;
                        busy       <= 1'b1;

                        state <= STATE_BIT_REVERSE;
                    end
                end

                STATE_BIT_REVERSE:
                begin
                    /*
                     * intt_load_we is asserted in this state.
                     */
                    if (copy_index == 4'd15)
                    begin
                        state <= STATE_INTT_LAUNCH;
                    end
                    else
                    begin
                        copy_index <= copy_index + 1'b1;
                    end
                end

                STATE_INTT_LAUNCH:
                begin
                    state <= STATE_INTT_WAIT;
                end

                STATE_INTT_WAIT:
                begin
                    if (intt_done)
                    begin
                        scale_index <= 4'd0;

                        state <= STATE_SCALE_LAUNCH;
                    end
                end

                STATE_SCALE_LAUNCH:
                begin
                    state <= STATE_SCALE_WAIT;
                end

                STATE_SCALE_WAIT:
                begin
                    if (scale_done)
                    begin
                        state <= STATE_SCALE_WRITE;
                    end
                end

                STATE_SCALE_WRITE:
                begin
                    output_memory[scale_index] <= scale_result;

                    if (scale_index == 4'd15)
                    begin
                        busy <= 1'b0;
                        done <= 1'b1;

                        state <= STATE_IDLE;
                    end
                    else
                    begin
                        scale_index <= scale_index + 1'b1;

                        state <= STATE_SCALE_LAUNCH;
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
