`timescale 1ns/1ps

/*
 * N=4096 pointwise modular multiplier.
 *
 * Before start, load A and B through their independent idle-time write
 * interfaces. After completion, read C synchronously through read_addr.
 *
 * For every coefficient:
 *
 *     C[j] = A[j] * B[j] mod q
 *
 * One timing-safe radix-4 modmul_core is reused for all 4096 products.
 */
module pointwise_mul4096_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic        load_a_we,
    input  logic [11:0] load_a_addr,
    input  logic [31:0] load_a_data,

    input  logic        load_b_we,
    input  logic [11:0] load_b_addr,
    input  logic [31:0] load_b_data,

    input  logic [11:0] read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [12:0] multiplication_count
);

    localparam logic [31:0] MODULUS =
        ntt4096_profile_pkg::NTT_Q;

    localparam integer TOTAL_COEFFICIENTS =
        4096;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_READ_ISSUE,
        STATE_READ_CAPTURE,
        STATE_MUL_START,
        STATE_MUL_WAIT,
        STATE_WRITEBACK
    } state_t;

    state_t state;

    logic        memory_a_enable;
    logic        memory_a_write_enable;
    logic [11:0] memory_a_address;
    logic [31:0] memory_a_write_data;
    logic [31:0] memory_a_read_data;
    logic [31:0] unused_memory_a_port_b_read_data;

    logic        memory_b_enable;
    logic        memory_b_write_enable;
    logic [11:0] memory_b_address;
    logic [31:0] memory_b_write_data;
    logic [31:0] memory_b_read_data;
    logic [31:0] unused_memory_b_port_b_read_data;

    logic        result_memory_enable;
    logic        result_memory_write_enable;
    logic [11:0] result_memory_address;
    logic [31:0] result_memory_write_data;
    logic [31:0] result_memory_read_data;
    logic [31:0] unused_result_memory_port_b_read_data;

    logic [11:0] coefficient_index;

    logic [31:0] captured_a;
    logic [31:0] captured_b;

    logic modmul_start;
    logic modmul_busy;
    logic modmul_done;
    logic [31:0] modmul_result;

    assign modmul_start =
        state == STATE_MUL_START;

    assign read_data =
        result_memory_read_data;

    always_comb
    begin
        memory_a_enable =
            1'b0;

        memory_a_write_enable =
            1'b0;

        memory_a_address =
            12'd0;

        memory_a_write_data =
            32'd0;

        if (!busy)
        begin
            memory_a_enable =
                load_a_we;

            memory_a_write_enable =
                load_a_we;

            memory_a_address =
                load_a_addr;

            memory_a_write_data =
                load_a_data;
        end
        else if (state == STATE_READ_ISSUE)
        begin
            memory_a_enable =
                1'b1;

            memory_a_address =
                coefficient_index;
        end
    end

    always_comb
    begin
        memory_b_enable =
            1'b0;

        memory_b_write_enable =
            1'b0;

        memory_b_address =
            12'd0;

        memory_b_write_data =
            32'd0;

        if (!busy)
        begin
            memory_b_enable =
                load_b_we;

            memory_b_write_enable =
                load_b_we;

            memory_b_address =
                load_b_addr;

            memory_b_write_data =
                load_b_data;
        end
        else if (state == STATE_READ_ISSUE)
        begin
            memory_b_enable =
                1'b1;

            memory_b_address =
                coefficient_index;
        end
    end

    always_comb
    begin
        result_memory_enable =
            1'b0;

        result_memory_write_enable =
            1'b0;

        result_memory_address =
            12'd0;

        result_memory_write_data =
            32'd0;

        if (!busy)
        begin
            result_memory_enable =
                1'b1;

            result_memory_address =
                read_addr;
        end
        else if (state == STATE_WRITEBACK)
        begin
            result_memory_enable =
                1'b1;

            result_memory_write_enable =
                1'b1;

            result_memory_address =
                coefficient_index;

            result_memory_write_data =
                modmul_result;
        end
    end

    ntt4096_coeff_bram memory_a (
        .clk                 (clk),

        .port_a_enable       (memory_a_enable),
        .port_a_write_enable (memory_a_write_enable),
        .port_a_address      (memory_a_address),
        .port_a_write_data   (memory_a_write_data),
        .port_a_read_data    (memory_a_read_data),

        .port_b_enable       (1'b0),
        .port_b_write_enable (1'b0),
        .port_b_address      (12'd0),
        .port_b_write_data   (32'd0),
        .port_b_read_data    (unused_memory_a_port_b_read_data)
    );

    ntt4096_coeff_bram memory_b (
        .clk                 (clk),

        .port_a_enable       (memory_b_enable),
        .port_a_write_enable (memory_b_write_enable),
        .port_a_address      (memory_b_address),
        .port_a_write_data   (memory_b_write_data),
        .port_a_read_data    (memory_b_read_data),

        .port_b_enable       (1'b0),
        .port_b_write_enable (1'b0),
        .port_b_address      (12'd0),
        .port_b_write_data   (32'd0),
        .port_b_read_data    (unused_memory_b_port_b_read_data)
    );

    modmul_core multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (modmul_start),

        .a       (captured_a),
        .b       (captured_b),
        .q       (MODULUS),

        .result  (modmul_result),
        .busy    (modmul_busy),
        .done    (modmul_done)
    );

    ntt4096_coeff_bram result_memory (
        .clk                 (clk),

        .port_a_enable       (result_memory_enable),
        .port_a_write_enable (result_memory_write_enable),
        .port_a_address      (result_memory_address),
        .port_a_write_data   (result_memory_write_data),
        .port_a_read_data    (result_memory_read_data),

        .port_b_enable       (1'b0),
        .port_b_write_enable (1'b0),
        .port_b_address      (12'd0),
        .port_b_write_data   (32'd0),
        .port_b_read_data    (unused_result_memory_port_b_read_data)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            busy <=
                1'b0;

            done <=
                1'b0;

            cycles <=
                32'd0;

            multiplication_count <=
                13'd0;

            coefficient_index <=
                12'd0;

            captured_a <=
                32'd0;

            captured_b <=
                32'd0;
        end
        else
        begin
            done <=
                1'b0;

            if (busy)
            begin
                cycles <=
                    cycles + 1'b1;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start)
                    begin
                        state <=
                            STATE_READ_ISSUE;

                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        multiplication_count <=
                            13'd0;

                        coefficient_index <=
                            12'd0;
                    end
                end

                STATE_READ_ISSUE:
                begin
                    state <=
                        STATE_READ_CAPTURE;
                end

                STATE_READ_CAPTURE:
                begin
                    captured_a <=
                        memory_a_read_data;

                    captured_b <=
                        memory_b_read_data;

                    state <=
                        STATE_MUL_START;
                end

                STATE_MUL_START:
                begin
                    state <=
                        STATE_MUL_WAIT;
                end

                STATE_MUL_WAIT:
                begin
                    if (modmul_done)
                    begin
                        state <=
                            STATE_WRITEBACK;
                    end
                end

                STATE_WRITEBACK:
                begin
                    multiplication_count <=
                        multiplication_count + 1'b1;

                    if (
                        coefficient_index
                        == TOTAL_COEFFICIENTS - 1
                    )
                    begin
                        state <=
                            STATE_IDLE;

                        busy <=
                            1'b0;

                        done <=
                            1'b1;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;

                        state <=
                            STATE_READ_ISSUE;
                    end
                end

                default:
                begin
                    state <=
                        STATE_IDLE;

                    busy <=
                        1'b0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            state == STATE_MUL_START
            && modmul_busy
        )
        begin
            $display(
                "ERROR: N=4096 pointwise multiplier start while busy"
            );

            $fatal(1);
        end
    end

`endif

endmodule
