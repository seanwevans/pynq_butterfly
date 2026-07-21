`timescale 1ns/1ps

/*
 * Registered OOC shell. The register boundary prevents common control/address
 * fanout from contaminating the arithmetic-core timing measurement.
 */
module poly_mul4096_four_butterfly_two_tower_synthesis_top (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic        load_a_we,
    input  logic [11:0] load_a_addr,
    input  logic [63:0] load_a_data,

    input  logic        load_b_we,
    input  logic [11:0] load_b_addr,
    input  logic [63:0] load_b_data,

    input  logic [11:0] read_a_addr,
    input  logic [11:0] read_b_addr,

    input  logic        profile_modulus_we,
    input  logic [63:0] profile_modulus_data,
    input  logic [61:0] profile_modulus_mu_data,

    input  logic        profile_we,
    input  logic [1:0]  profile_bank,
    input  logic [11:0] profile_addr,
    input  logic [63:0] profile_data,

    input  logic        profile_commit,

    output logic [63:0] read_a_data,
    output logic [63:0] read_b_data,

    output logic        profile_ready,
    output logic [63:0] active_modulus,
    output logic [61:0] active_modulus_mu,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles_lane0,
    output logic [31:0] cycles_lane1,

    output logic [16:0] multiplication_count_lane0,
    output logic [16:0] multiplication_count_lane1
);

    logic reset_n_q;
    logic start_q;

    logic load_a_we_q;
    logic [11:0] load_a_addr_q;
    logic [63:0] load_a_data_q;

    logic load_b_we_q;
    logic [11:0] load_b_addr_q;
    logic [63:0] load_b_data_q;

    logic [11:0] read_a_addr_q;
    logic [11:0] read_b_addr_q;

    logic profile_modulus_we_q;
    logic [63:0] profile_modulus_data_q;
    logic [61:0] profile_modulus_mu_data_q;

    logic profile_we_q;
    logic [1:0] profile_bank_q;
    logic [11:0] profile_addr_q;
    logic [63:0] profile_data_q;

    logic profile_commit_q;

    logic [63:0] inner_read_a_data;
    logic [63:0] inner_read_b_data;
    logic inner_profile_ready;
    logic [63:0] inner_active_modulus;
    logic [61:0] inner_active_modulus_mu;
    logic inner_busy;
    logic inner_done;
    logic [31:0] inner_cycles_lane0;
    logic [31:0] inner_cycles_lane1;
    logic [16:0] inner_multiplication_count_lane0;
    logic [16:0] inner_multiplication_count_lane1;

    always_ff @(posedge clk)
    begin
        reset_n_q <= reset_n;
        start_q <= start;

        load_a_we_q <= load_a_we;
        load_a_addr_q <= load_a_addr;
        load_a_data_q <= load_a_data;

        load_b_we_q <= load_b_we;
        load_b_addr_q <= load_b_addr;
        load_b_data_q <= load_b_data;

        read_a_addr_q <= read_a_addr;
        read_b_addr_q <= read_b_addr;

        profile_modulus_we_q <= profile_modulus_we;
        profile_modulus_data_q <= profile_modulus_data;
        profile_modulus_mu_data_q <= profile_modulus_mu_data;

        profile_we_q <= profile_we;
        profile_bank_q <= profile_bank;
        profile_addr_q <= profile_addr;
        profile_data_q <= profile_data;

        profile_commit_q <= profile_commit;

        read_a_data <= inner_read_a_data;
        read_b_data <= inner_read_b_data;
        profile_ready <= inner_profile_ready;
        active_modulus <= inner_active_modulus;
        active_modulus_mu <= inner_active_modulus_mu;
        busy <= inner_busy;
        done <= inner_done;
        cycles_lane0 <= inner_cycles_lane0;
        cycles_lane1 <= inner_cycles_lane1;
        multiplication_count_lane0 <=
            inner_multiplication_count_lane0;
        multiplication_count_lane1 <=
            inner_multiplication_count_lane1;
    end

    poly_mul4096_four_butterfly_two_tower_core core (
        .clk                       (clk),
        .reset_n                   (reset_n_q),
        .start                     (start_q),

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

        .profile_modulus_we        (profile_modulus_we_q),
        .profile_modulus_data      (profile_modulus_data_q),
        .profile_modulus_mu_data   (profile_modulus_mu_data_q),

        .profile_we                (profile_we_q),
        .profile_bank              (profile_bank_q),
        .profile_addr              (profile_addr_q),
        .profile_data              (profile_data_q),

        .profile_commit            (profile_commit_q),

        .profile_ready             (inner_profile_ready),
        .active_modulus            (inner_active_modulus),
        .active_modulus_mu         (inner_active_modulus_mu),

        .busy                      (inner_busy),
        .done                      (inner_done),

        .cycles_lane0              (inner_cycles_lane0),
        .cycles_lane1              (inner_cycles_lane1),

        .multiplication_count_lane0(
            inner_multiplication_count_lane0
        ),
        .multiplication_count_lane1(
            inner_multiplication_count_lane1
        )
    );

endmodule
