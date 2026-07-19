`timescale 1ns/1ps

/*
 * Complete N=16 forward/inverse negacyclic NTT round-trip engine.
 *
 * Input:
 *     sixteen natural-order coefficients
 *
 * Pipeline:
 *     natural coefficients
 *         -> forward negacyclic NTT
 *         -> internal coefficient transfer
 *         -> inverse negacyclic NTT
 *         -> recovered natural coefficients
 *
 * This wrapper verifies that the forward and inverse hardware
 * conventions agree without software preprocessing between them.
 */
module ntt16_roundtrip_core (
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

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_FORWARD_LOAD,
        STATE_FORWARD_START,
        STATE_FORWARD_WAIT,
        STATE_TRANSFER,
        STATE_INVERSE_START,
        STATE_INVERSE_WAIT
    } state_t;

    state_t state;

    logic [31:0] input_memory [0:15];

    logic [3:0] coefficient_index;

    logic        forward_start;
    logic        forward_load_we;
    logic [3:0]  forward_load_addr;
    logic [31:0] forward_load_data;

    logic [3:0]  forward_read_addr;
    logic [31:0] forward_read_data;

    logic forward_busy;
    logic forward_done;
    logic forward_preprocess_done;

    logic        inverse_start;
    logic        inverse_load_we;
    logic [3:0]  inverse_load_addr;
    logic [31:0] inverse_load_data;

    logic [3:0]  inverse_read_addr;
    logic [31:0] inverse_read_data;

    logic inverse_busy;
    logic inverse_done;

    /*
     * Load the original coefficients into the forward engine.
     */
    assign forward_load_we =
        state == STATE_FORWARD_LOAD;

    assign forward_load_addr =
        coefficient_index;

    assign forward_load_data =
        input_memory[coefficient_index];

    assign forward_start =
        state == STATE_FORWARD_START;

    /*
     * Read each completed forward coefficient while transferring
     * it into the inverse engine.
     */
    assign forward_read_addr =
        coefficient_index;

    /*
     * Transfer one natural-order forward coefficient per clock.
     */
    assign inverse_load_we =
        state == STATE_TRANSFER;

    assign inverse_load_addr =
        coefficient_index;

    assign inverse_load_data =
        forward_read_data;

    assign inverse_start =
        state == STATE_INVERSE_START;

    assign inverse_read_addr =
        read_addr;

    assign read_data =
        inverse_read_data;

    forward_ntt16_core forward_engine (
        .clk             (clk),
        .reset_n         (reset_n),
        .start           (forward_start),

        .load_we         (forward_load_we),
        .load_addr       (forward_load_addr),
        .load_data       (forward_load_data),

        .read_addr       (forward_read_addr),
        .read_data       (forward_read_data),

        .busy            (forward_busy),
        .done            (forward_done),

        .preprocess_done (forward_preprocess_done)
    );

    inverse_ntt16_core inverse_engine (
        .clk       (clk),
        .reset_n   (reset_n),
        .start     (inverse_start),

        .load_we   (inverse_load_we),
        .load_addr (inverse_load_addr),
        .load_data (inverse_load_data),

        .read_addr (inverse_read_addr),
        .read_data (inverse_read_data),

        .busy      (inverse_busy),
        .done      (inverse_done)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;

            coefficient_index <= 4'd0;

            busy <= 1'b0;
            done <= 1'b0;
        end
        else
        begin
            done <= 1'b0;

            /*
             * Accept a new natural-order source vector only while
             * the complete round-trip engine is idle.
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
                        coefficient_index <= 4'd0;
                        busy              <= 1'b1;

                        state <= STATE_FORWARD_LOAD;
                    end
                end

                STATE_FORWARD_LOAD:
                begin
                    /*
                     * forward_load_we is asserted during this state.
                     * One coefficient is written at each rising edge.
                     */
                    if (coefficient_index == 4'd15)
                    begin
                        coefficient_index <= 4'd0;

                        state <= STATE_FORWARD_START;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;
                    end
                end

                STATE_FORWARD_START:
                begin
                    /*
                     * forward_start is asserted for this clock.
                     */
                    state <= STATE_FORWARD_WAIT;
                end

                STATE_FORWARD_WAIT:
                begin
                    if (forward_done)
                    begin
                        coefficient_index <= 4'd0;

                        state <= STATE_TRANSFER;
                    end
                end

                STATE_TRANSFER:
                begin
                    /*
                     * forward_read_data is asynchronous.
                     * inverse_load_we writes it into the inverse
                     * engine at this rising edge.
                     */
                    if (coefficient_index == 4'd15)
                    begin
                        coefficient_index <= 4'd0;

                        state <= STATE_INVERSE_START;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;
                    end
                end

                STATE_INVERSE_START:
                begin
                    /*
                     * inverse_start is asserted for this clock.
                     */
                    state <= STATE_INVERSE_WAIT;
                end

                STATE_INVERSE_WAIT:
                begin
                    if (inverse_done)
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
