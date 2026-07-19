`timescale 1ns/1ps

/*
 * Complete N=16 forward negacyclic NTT for the fixed profile:
 *
 * OpenFHE 1.5.1 COMPOSITESCALINGAUTO
 * tower 0
 *
 * q     = 1073692673
 * psi   = 763394433
 * omega = psi^2 mod q = 1051583792
 *
 * Input:
 *     sixteen natural-order coefficients
 *
 * Preprocessing:
 *     twisted[j] = input[j] * psi^j mod q
 *
 * Placement:
 *     twisted[j] is written to bit_reverse(j)
 *
 * Transform:
 *     four-stage radix-2 DIT cyclic NTT
 *
 * Output:
 *     natural-order forward negacyclic NTT
 */
module forward_ntt16_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    /*
     * Natural-order input loading interface.
     *
     * Writes are accepted only while the complete core is idle.
     */
    input  logic        load_we,
    input  logic [3:0]  load_addr,
    input  logic [31:0] load_data,

    /*
     * Natural-order transform-output read interface.
     */
    input  logic [3:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    /*
     * Pulses after all sixteen twist multiplications and
     * bit-reversed writes have completed.
     */
    output logic        preprocess_done
);

    localparam logic [31:0] PROFILE_Q =
        32'd1073692673;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_PREP_LAUNCH,
        STATE_PREP_WAIT,
        STATE_PREP_WRITE,
        STATE_NTT_LAUNCH,
        STATE_NTT_WAIT
    } state_t;

    state_t state;

    /*
     * Original natural-order coefficients.
     */
    logic [31:0] input_memory [0:15];

    logic [3:0] prep_index;

    logic [31:0] twist_factor;

    logic        twist_start;
    logic [31:0] twist_result;
    logic        twist_busy;
    logic        twist_done;

    logic        ntt_start;
    logic        ntt_load_we;
    logic [3:0]  ntt_load_addr;
    logic [31:0] ntt_load_data;

    logic [31:0] ntt_read_data;

    logic        ntt_busy;
    logic        ntt_done;
    logic        ntt_stage_done;
    logic [1:0]  ntt_stage_completed;

    /*
     * Reverse the four address bits.
     *
     * Examples:
     *     1  -> 8
     *     2  -> 4
     *     3  -> 12
     *     15 -> 15
     */
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
     * psi^j mod q for j in [0, 15].
     *
     * These constants come from the validated OpenFHE profile.
     */
    function automatic logic [31:0] twist_for(
        input logic [3:0] index
    );
        begin
            case (index)
                4'd0:
                    twist_for = 32'd1;

                4'd1:
                    twist_for = 32'd763394433;

                4'd2:
                    twist_for = 32'd1051583792;

                4'd3:
                    twist_for = 32'd412848016;

                4'd4:
                    twist_for = 32'd808610892;

                4'd5:
                    twist_for = 32'd852239105;

                4'd6:
                    twist_for = 32'd286011093;

                4'd7:
                    twist_for = 32'd455809104;

                4'd8:
                    twist_for = 32'd8388480;

                4'd9:
                    twist_for = 32'd19332567;

                4'd10:
                    twist_for = 32'd103009083;

                4'd11:
                    twist_for = 32'd598196351;

                4'd12:
                    twist_for = 32'd412890215;

                4'd13:
                    twist_for = 32'd215328367;

                4'd14:
                    twist_for = 32'd918502623;

                4'd15:
                    twist_for = 32'd322126179;

                default:
                    twist_for = 32'd1;
            endcase
        end
    endfunction

    assign twist_factor =
        twist_for(prep_index);

    /*
     * One launch-state clock produces one multiplication start pulse.
     */
    assign twist_start =
        state == STATE_PREP_LAUNCH;

    modmul_core twist_multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (twist_start),

        .a       (twist_factor),
        .b       (input_memory[prep_index]),
        .q       (PROFILE_Q),

        .result  (twist_result),
        .busy    (twist_busy),
        .done    (twist_done)
    );

    /*
     * During STATE_PREP_WRITE, the completed twisted coefficient is
     * written directly into its bit-reversed NTT memory address.
     */
    assign ntt_load_we =
        state == STATE_PREP_WRITE;

    assign ntt_load_addr =
        bit_reverse4(prep_index);

    assign ntt_load_data =
        twist_result;

    /*
     * One launch-state clock produces one NTT start pulse.
     */
    assign ntt_start =
        state == STATE_NTT_LAUNCH;

    ntt16_core cyclic_ntt (
        .clk             (clk),
        .reset_n         (reset_n),
        .start           (ntt_start),

        .q               (PROFILE_Q),

        .load_we         (ntt_load_we),
        .load_addr       (ntt_load_addr),
        .load_data       (ntt_load_data),

        .read_addr       (read_addr),
        .read_data       (ntt_read_data),

        .busy            (ntt_busy),
        .done            (ntt_done),

        .stage_done      (ntt_stage_done),
        .stage_completed (ntt_stage_completed)
    );

    assign read_data =
        ntt_read_data;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;

            prep_index <= 4'd0;

            busy <= 1'b0;
            done <= 1'b0;

            preprocess_done <= 1'b0;
        end
        else
        begin
            done            <= 1'b0;
            preprocess_done <= 1'b0;

            /*
             * Accept natural-order coefficients only when the
             * complete forward transform engine is idle.
             */
            if (load_we && !busy)
            begin
                input_memory[load_addr] <= load_data;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start && !busy)
                    begin
                        prep_index <= 4'd0;
                        busy       <= 1'b1;

                        state <= STATE_PREP_LAUNCH;
                    end
                end

                STATE_PREP_LAUNCH:
                begin
                    /*
                     * twist_start is asserted during this state.
                     * modmul_core samples its operands at this edge.
                     */
                    state <= STATE_PREP_WAIT;
                end

                STATE_PREP_WAIT:
                begin
                    if (twist_done)
                    begin
                        state <= STATE_PREP_WRITE;
                    end
                end

                STATE_PREP_WRITE:
                begin
                    /*
                     * ntt_load_we is asserted during this state.
                     * ntt16_core writes twist_result at this edge.
                     */
                    if (prep_index == 4'd15)
                    begin
                        preprocess_done <= 1'b1;

                        state <= STATE_NTT_LAUNCH;
                    end
                    else
                    begin
                        prep_index <= prep_index + 1'b1;

                        state <= STATE_PREP_LAUNCH;
                    end
                end

                STATE_NTT_LAUNCH:
                begin
                    /*
                     * ntt_start is asserted during this state.
                     */
                    state <= STATE_NTT_WAIT;
                end

                STATE_NTT_WAIT:
                begin
                    if (ntt_done)
                    begin
                        busy <= 1'b0;
                        done <= 1'b1;

                        state <= STATE_IDLE;
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
