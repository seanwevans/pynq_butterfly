`timescale 1ns/1ps

/*
 * Sixteen-element pointwise modular multiplier.
 *
 * For each coefficient index j:
 *
 *     output[j] = input_a[j] * input_b[j] mod q
 *
 * This is the multiplication operation performed between the forward
 * and inverse NTTs in an NTT-based polynomial multiplier.
 */
module pointwise_mul16_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic [31:0] q,

    /*
     * Input loading interface.
     *
     * load_bank = 0 selects input A.
     * load_bank = 1 selects input B.
     *
     * Writes are accepted only while idle.
     */
    input  logic        load_we,
    input  logic        load_bank,
    input  logic [3:0]  load_addr,
    input  logic [31:0] load_data,

    /*
     * Natural-order result read interface.
     */
    input  logic [3:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done
);

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_LAUNCH,
        STATE_WAIT
    } state_t;

    state_t state;

    logic [31:0] input_a [0:15];
    logic [31:0] input_b [0:15];
    logic [31:0] output_memory [0:15];

    logic [31:0] q_hold;
    logic [3:0] coefficient_index;

    logic        multiplier_start;
    logic [31:0] multiplier_result;
    logic        multiplier_busy;
    logic        multiplier_done;

    assign read_data =
        output_memory[read_addr];

    /*
     * STATE_LAUNCH lasts one clock and therefore generates one
     * multiplier start pulse.
     */
    assign multiplier_start =
        state == STATE_LAUNCH;

    modmul_core multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (multiplier_start),

        .a       (input_a[coefficient_index]),
        .b       (input_b[coefficient_index]),
        .q       (q_hold),

        .result  (multiplier_result),
        .busy    (multiplier_busy),
        .done    (multiplier_done)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;

            q_hold           <= 32'd0;
            coefficient_index <= 4'd0;

            busy <= 1'b0;
            done <= 1'b0;
        end
        else
        begin
            done <= 1'b0;

            if (load_we && !busy)
            begin
                if (load_bank)
                    input_b[load_addr] <= load_data;
                else
                    input_a[load_addr] <= load_data;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start && !busy)
                    begin
                        q_hold            <= q;
                        coefficient_index <= 4'd0;

                        busy <= 1'b1;

                        state <= STATE_LAUNCH;
                    end
                end

                STATE_LAUNCH:
                begin
                    /*
                     * multiplier_start is asserted during this state.
                     */
                    state <= STATE_WAIT;
                end

                STATE_WAIT:
                begin
                    if (multiplier_done)
                    begin
                        output_memory[coefficient_index] <=
                            multiplier_result;

                        if (coefficient_index == 4'd15)
                        begin
                            busy <= 1'b0;
                            done <= 1'b1;

                            state <= STATE_IDLE;
                        end
                        else
                        begin
                            coefficient_index <=
                                coefficient_index + 1'b1;

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
