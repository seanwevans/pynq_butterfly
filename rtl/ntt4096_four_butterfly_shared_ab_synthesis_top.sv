`timescale 1ns/1ps

/*
 * Registered implementation shell for the shared-A/B NTT phase core.
 */
module ntt4096_four_butterfly_shared_ab_synthesis_top (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        modulus_we,
    input  logic [31:0] modulus_data,
    input  logic [30:0] modulus_mu_data,

    input  logic        forward_twiddle_we,
    input  logic [11:0] forward_twiddle_addr,
    input  logic [31:0] forward_twiddle_data,

    input  logic        inverse_twiddle_we,
    input  logic [11:0] inverse_twiddle_addr,
    input  logic [31:0] inverse_twiddle_data,

    input  logic        load_a_we,
    input  logic [11:0] load_a_addr,
    input  logic [31:0] load_a_data,

    input  logic        load_b_we,
    input  logic [11:0] load_b_addr,
    input  logic [31:0] load_b_data,

    input  logic [11:0] read_a_addr,
    input  logic [11:0] read_b_addr,

    input  logic        start,

    output logic [31:0] read_a_data,
    output logic [31:0] read_b_data,

    output logic        busy,
    output logic        done,
    output logic [31:0] cycles,

    output logic [1:0]  transform_count,
    output logic [15:0] forward_butterfly_count,
    output logic [14:0] inverse_butterfly_count
);

    logic        reset_n_q;

    logic        modulus_we_q;
    logic [31:0] modulus_data_q;
    logic [30:0] modulus_mu_data_q;

    logic        forward_twiddle_we_q;
    logic [11:0] forward_twiddle_addr_q;
    logic [31:0] forward_twiddle_data_q;

    logic        inverse_twiddle_we_q;
    logic [11:0] inverse_twiddle_addr_q;
    logic [31:0] inverse_twiddle_data_q;

    logic        load_a_we_q;
    logic [11:0] load_a_addr_q;
    logic [31:0] load_a_data_q;

    logic        load_b_we_q;
    logic [11:0] load_b_addr_q;
    logic [31:0] load_b_data_q;

    logic [11:0] read_a_addr_q;
    logic [11:0] read_b_addr_q;

    logic start_q;

    logic [31:0] inner_read_a_data;
    logic [31:0] inner_read_b_data;

    logic        inner_busy;
    logic        inner_done;
    logic [31:0] inner_cycles;

    logic [1:0]  inner_transform_count;
    logic [15:0] inner_forward_butterfly_count;
    logic [14:0] inner_inverse_butterfly_count;

    always_ff @(posedge clk)
    begin
        reset_n_q <=
            reset_n;

        modulus_we_q <=
            modulus_we;

        modulus_data_q <=
            modulus_data;

        modulus_mu_data_q <=
            modulus_mu_data;

        forward_twiddle_we_q <=
            forward_twiddle_we;

        forward_twiddle_addr_q <=
            forward_twiddle_addr;

        forward_twiddle_data_q <=
            forward_twiddle_data;

        inverse_twiddle_we_q <=
            inverse_twiddle_we;

        inverse_twiddle_addr_q <=
            inverse_twiddle_addr;

        inverse_twiddle_data_q <=
            inverse_twiddle_data;

        load_a_we_q <=
            load_a_we;

        load_a_addr_q <=
            load_a_addr;

        load_a_data_q <=
            load_a_data;

        load_b_we_q <=
            load_b_we;

        load_b_addr_q <=
            load_b_addr;

        load_b_data_q <=
            load_b_data;

        read_a_addr_q <=
            read_a_addr;

        read_b_addr_q <=
            read_b_addr;

        start_q <=
            start;

        read_a_data <=
            inner_read_a_data;

        read_b_data <=
            inner_read_b_data;

        busy <=
            inner_busy;

        done <=
            inner_done;

        cycles <=
            inner_cycles;

        transform_count <=
            inner_transform_count;

        forward_butterfly_count <=
            inner_forward_butterfly_count;

        inverse_butterfly_count <=
            inner_inverse_butterfly_count;
    end

    ntt4096_four_butterfly_shared_ab_core core (
        .clk                       (clk),
        .reset_n                   (reset_n_q),

        .modulus_we                (modulus_we_q),
        .modulus_data              (modulus_data_q),
        .modulus_mu_data           (modulus_mu_data_q),

        .forward_twiddle_we        (forward_twiddle_we_q),
        .forward_twiddle_addr      (forward_twiddle_addr_q),
        .forward_twiddle_data      (forward_twiddle_data_q),

        .inverse_twiddle_we        (inverse_twiddle_we_q),
        .inverse_twiddle_addr      (inverse_twiddle_addr_q),
        .inverse_twiddle_data      (inverse_twiddle_data_q),

        .load_a_we                 (load_a_we_q),
        .load_a_addr               (load_a_addr_q),
        .load_a_data               (load_a_data_q),

        .load_b_we                 (load_b_we_q),
        .load_b_addr               (load_b_addr_q),
        .load_b_data               (load_b_data_q),

        .read_a_addr               (read_a_addr_q),
        .read_a_data               (inner_read_a_data),

        .read_b_addr               (read_b_addr_q),
        .read_b_data               (inner_read_b_data),

        .start                     (start_q),

        .busy                      (inner_busy),
        .done                      (inner_done),
        .cycles                    (inner_cycles),

        .transform_count           (inner_transform_count),
        .forward_butterfly_count   (
            inner_forward_butterfly_count
        ),
        .inverse_butterfly_count   (
            inner_inverse_butterfly_count
        )
    );

endmodule
