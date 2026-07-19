`timescale 1ns/1ps

/*
 * Complete N=16 negacyclic polynomial multiplier.
 *
 * Computes:
 *
 *     C(X) = A(X) * B(X) mod (X^16 + 1, q)
 *
 * Pipeline:
 *
 *     A -> forward negacyclic NTT
 *     B -> forward negacyclic NTT
 *
 *     transformed_A[j] * transformed_B[j] mod q
 *
 *     -> inverse negacyclic NTT
 *     -> natural-order product coefficients
 *
 * Fixed OpenFHE-derived profile:
 *
 *     q = 1073692673
 */
module poly_mul16_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    /*
     * Natural-order polynomial loading interface.
     *
     * load_bank = 0 selects polynomial A.
     * load_bank = 1 selects polynomial B.
     */
    input  logic        load_we,
    input  logic        load_bank,
    input  logic [3:0]  load_addr,
    input  logic [31:0] load_data,

    /*
     * Natural-order product read interface.
     */
    input  logic [3:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done
);

    localparam logic [31:0] PROFILE_Q =
        32'd1073692673;

    typedef enum logic [3:0] {
        STATE_IDLE,

        STATE_FORWARD_A_LOAD,
        STATE_FORWARD_A_START,
        STATE_FORWARD_A_WAIT,
        STATE_TRANSFER_A,

        STATE_FORWARD_B_LOAD,
        STATE_FORWARD_B_START,
        STATE_FORWARD_B_WAIT,
        STATE_TRANSFER_B,

        STATE_POINTWISE_START,
        STATE_POINTWISE_WAIT,
        STATE_TRANSFER_PRODUCT,

        STATE_INVERSE_START,
        STATE_INVERSE_WAIT
    } state_t;

    state_t state;

    logic [31:0] polynomial_a [0:15];
    logic [31:0] polynomial_b [0:15];

    logic [3:0] coefficient_index;

    /*
     * Forward-transform engine signals.
     */
    logic        forward_start;

    logic        forward_load_we;
    logic [3:0]  forward_load_addr;
    logic [31:0] forward_load_data;

    logic [3:0]  forward_read_addr;
    logic [31:0] forward_read_data;

    logic forward_busy;
    logic forward_done;
    logic forward_preprocess_done;

    /*
     * Pointwise multiplier signals.
     */
    logic        pointwise_start;

    logic        pointwise_load_we;
    logic        pointwise_load_bank;
    logic [3:0]  pointwise_load_addr;
    logic [31:0] pointwise_load_data;

    logic [3:0]  pointwise_read_addr;
    logic [31:0] pointwise_read_data;

    logic pointwise_busy;
    logic pointwise_done;

    /*
     * Inverse-transform engine signals.
     */
    logic        inverse_start;

    logic        inverse_load_we;
    logic [3:0]  inverse_load_addr;
    logic [31:0] inverse_load_data;

    logic [3:0]  inverse_read_addr;
    logic [31:0] inverse_read_data;

    logic inverse_busy;
    logic inverse_done;

    /*
     * Load either source polynomial into the reusable forward engine.
     */
    assign forward_load_we =
        (state == STATE_FORWARD_A_LOAD) ||
        (state == STATE_FORWARD_B_LOAD);

    assign forward_load_addr =
        coefficient_index;

    assign forward_load_data =
        (state == STATE_FORWARD_A_LOAD)
            ? polynomial_a[coefficient_index]
            : polynomial_b[coefficient_index];

    assign forward_start =
        (state == STATE_FORWARD_A_START) ||
        (state == STATE_FORWARD_B_START);

    /*
     * Read the completed forward transform coefficient currently
     * being transferred into the pointwise engine.
     */
    assign forward_read_addr =
        coefficient_index;

    /*
     * Transfer forward-transform results into pointwise bank A or B.
     */
    assign pointwise_load_we =
        (state == STATE_TRANSFER_A) ||
        (state == STATE_TRANSFER_B);

    assign pointwise_load_bank =
        state == STATE_TRANSFER_B;

    assign pointwise_load_addr =
        coefficient_index;

    assign pointwise_load_data =
        forward_read_data;

    assign pointwise_start =
        state == STATE_POINTWISE_START;

    /*
     * Read the current pointwise product for transfer into the
     * inverse-transform engine.
     */
    assign pointwise_read_addr =
        coefficient_index;

    assign inverse_load_we =
        state == STATE_TRANSFER_PRODUCT;

    assign inverse_load_addr =
        coefficient_index;

    assign inverse_load_data =
        pointwise_read_data;

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

    pointwise_mul16_core pointwise_engine (
        .clk       (clk),
        .reset_n   (reset_n),
        .start     (pointwise_start),

        .q         (PROFILE_Q),

        .load_we   (pointwise_load_we),
        .load_bank (pointwise_load_bank),
        .load_addr (pointwise_load_addr),
        .load_data (pointwise_load_data),

        .read_addr (pointwise_read_addr),
        .read_data (pointwise_read_data),

        .busy      (pointwise_busy),
        .done      (pointwise_done)
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
             * Accept source coefficients only while the complete
             * multiplier is idle.
             */
            if (load_we && !busy)
            begin
                if (load_bank)
                    polynomial_b[load_addr] <= load_data;
                else
                    polynomial_a[load_addr] <= load_data;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start && !busy)
                    begin
                        coefficient_index <= 4'd0;
                        busy              <= 1'b1;

                        state <= STATE_FORWARD_A_LOAD;
                    end
                end

                STATE_FORWARD_A_LOAD:
                begin
                    /*
                     * One coefficient is written into the forward
                     * engine on each rising edge.
                     */
                    if (coefficient_index == 4'd15)
                    begin
                        coefficient_index <= 4'd0;
                        state <= STATE_FORWARD_A_START;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;
                    end
                end

                STATE_FORWARD_A_START:
                begin
                    state <= STATE_FORWARD_A_WAIT;
                end

                STATE_FORWARD_A_WAIT:
                begin
                    if (forward_done)
                    begin
                        coefficient_index <= 4'd0;
                        state <= STATE_TRANSFER_A;
                    end
                end

                STATE_TRANSFER_A:
                begin
                    /*
                     * Transfer transformed polynomial A into
                     * pointwise input bank A.
                     */
                    if (coefficient_index == 4'd15)
                    begin
                        coefficient_index <= 4'd0;
                        state <= STATE_FORWARD_B_LOAD;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;
                    end
                end

                STATE_FORWARD_B_LOAD:
                begin
                    if (coefficient_index == 4'd15)
                    begin
                        coefficient_index <= 4'd0;
                        state <= STATE_FORWARD_B_START;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;
                    end
                end

                STATE_FORWARD_B_START:
                begin
                    state <= STATE_FORWARD_B_WAIT;
                end

                STATE_FORWARD_B_WAIT:
                begin
                    if (forward_done)
                    begin
                        coefficient_index <= 4'd0;
                        state <= STATE_TRANSFER_B;
                    end
                end

                STATE_TRANSFER_B:
                begin
                    /*
                     * Transfer transformed polynomial B into
                     * pointwise input bank B.
                     */
                    if (coefficient_index == 4'd15)
                    begin
                        coefficient_index <= 4'd0;
                        state <= STATE_POINTWISE_START;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;
                    end
                end

                STATE_POINTWISE_START:
                begin
                    state <= STATE_POINTWISE_WAIT;
                end

                STATE_POINTWISE_WAIT:
                begin
                    if (pointwise_done)
                    begin
                        coefficient_index <= 4'd0;
                        state <= STATE_TRANSFER_PRODUCT;
                    end
                end

                STATE_TRANSFER_PRODUCT:
                begin
                    /*
                     * Transfer pointwise products into the inverse
                     * transform engine.
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
