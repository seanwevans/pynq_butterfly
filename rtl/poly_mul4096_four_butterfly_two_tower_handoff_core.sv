`timescale 1ns/1ps

/* Two exact four-butterfly RNS towers with a shared four-wide idle handoff. */
module poly_mul4096_four_butterfly_two_tower_handoff_core (
    input  logic              clk,
    input  logic              reset_n,
    input  logic              start,

    input  logic              load_a_we,
    input  logic [11:0]       load_a_addr,
    input  logic [63:0]       load_a_data,

    input  logic              load_b_we,
    input  logic [11:0]       load_b_addr,
    input  logic [63:0]       load_b_data,

    input  logic [11:0]       read_a_addr,
    output logic [63:0]       read_a_data,

    input  logic [11:0]       read_b_addr,
    output logic [63:0]       read_b_data,

    input  logic              handoff_read_valid,
    input  logic [11:0]       handoff_read_base,
    output logic              handoff_read_data_valid,
    output logic [3:0][63:0]  handoff_read_data,

    input  logic              handoff_write_valid,
    input  logic [11:0]       handoff_write_base,
    input  logic [3:0][63:0]  handoff_write_a_data,
    input  logic [3:0][63:0]  handoff_write_b_data,

    input  logic              profile_modulus_we,
    input  logic [63:0]       profile_modulus_data,
    input  logic [61:0]       profile_modulus_mu_data,

    input  logic              profile_we,
    input  logic [1:0]        profile_bank,
    input  logic [11:0]       profile_addr,
    input  logic [63:0]       profile_data,

    input  logic              profile_commit,

    output logic              profile_ready,
    output logic [63:0]       active_modulus,
    output logic [61:0]       active_modulus_mu,

    output logic              busy,
    output logic              done,

    output logic [31:0]       cycles_lane0,
    output logic [31:0]       cycles_lane1,

    output logic [16:0]       multiplication_count_lane0,
    output logic [16:0]       multiplication_count_lane1
);

    logic lane0_profile_ready;
    logic lane1_profile_ready;
    logic lane0_busy;
    logic lane1_busy;
    logic lane0_done;
    logic lane1_done;
    logic lane0_handoff_read_data_valid;
    logic lane1_handoff_read_data_valid;

    logic [31:0] lane0_active_modulus;
    logic [31:0] lane1_active_modulus;
    logic [30:0] lane0_active_mu;
    logic [30:0] lane1_active_mu;
    logic [31:0] lane0_read_a_data;
    logic [31:0] lane1_read_a_data;
    logic [31:0] lane0_read_b_data;
    logic [31:0] lane1_read_b_data;

    logic [3:0][31:0] lane0_handoff_read_data;
    logic [3:0][31:0] lane1_handoff_read_data;
    logic [3:0][31:0] lane0_handoff_write_a_data;
    logic [3:0][31:0] lane1_handoff_write_a_data;
    logic [3:0][31:0] lane0_handoff_write_b_data;
    logic [3:0][31:0] lane1_handoff_write_b_data;

    logic [13:0] unused_preprocessing_count_lane0;
    logic [13:0] unused_preprocessing_count_lane1;
    logic [15:0] unused_forward_count_lane0;
    logic [15:0] unused_forward_count_lane1;
    logic [12:0] unused_pointwise_count_lane0;
    logic [12:0] unused_pointwise_count_lane1;
    logic [14:0] unused_inverse_count_lane0;
    logic [14:0] unused_inverse_count_lane1;
    logic [12:0] unused_postprocessing_count_lane0;
    logic [12:0] unused_postprocessing_count_lane1;

    assign profile_ready =
        lane0_profile_ready
        && lane1_profile_ready;

    assign active_modulus = {
        lane1_active_modulus,
        lane0_active_modulus
    };

    assign active_modulus_mu = {
        lane1_active_mu,
        lane0_active_mu
    };

    assign busy =
        lane0_busy
        || lane1_busy;

    assign done =
        lane0_done
        && lane1_done;

    assign read_a_data = {
        lane1_read_a_data,
        lane0_read_a_data
    };

    assign read_b_data = {
        lane1_read_b_data,
        lane0_read_b_data
    };

    assign handoff_read_data_valid =
        lane0_handoff_read_data_valid
        && lane1_handoff_read_data_valid;

    generate
        genvar lane;

        for (lane = 0; lane < 4; lane = lane + 1)
        begin : pair_handoff_lanes
            assign lane0_handoff_write_a_data[lane] =
                handoff_write_a_data[lane][31:0];

            assign lane1_handoff_write_a_data[lane] =
                handoff_write_a_data[lane][63:32];

            assign lane0_handoff_write_b_data[lane] =
                handoff_write_b_data[lane][31:0];

            assign lane1_handoff_write_b_data[lane] =
                handoff_write_b_data[lane][63:32];

            assign handoff_read_data[lane] = {
                lane1_handoff_read_data[lane],
                lane0_handoff_read_data[lane]
            };
        end
    endgenerate

    poly_mul4096_four_butterfly_pipeline_runtime_profile_handoff_core lane0 (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .start                     (start),
        .load_a_we                 (load_a_we),
        .load_a_addr               (load_a_addr),
        .load_a_data               (load_a_data[31:0]),
        .load_b_we                 (load_b_we),
        .load_b_addr               (load_b_addr),
        .load_b_data               (load_b_data[31:0]),
        .read_a_addr               (read_a_addr),
        .read_a_data               (lane0_read_a_data),
        .read_b_addr               (read_b_addr),
        .read_b_data               (lane0_read_b_data),
        .handoff_read_valid        (handoff_read_valid),
        .handoff_read_base         (handoff_read_base),
        .handoff_read_data_valid   (lane0_handoff_read_data_valid),
        .handoff_read_data         (lane0_handoff_read_data),
        .handoff_write_valid       (handoff_write_valid),
        .handoff_write_base        (handoff_write_base),
        .handoff_write_a_data      (lane0_handoff_write_a_data),
        .handoff_write_b_data      (lane0_handoff_write_b_data),
        .profile_modulus_we        (profile_modulus_we),
        .profile_modulus_data      (profile_modulus_data[31:0]),
        .profile_modulus_mu_data   (profile_modulus_mu_data[30:0]),
        .profile_we                (profile_we),
        .profile_bank              (profile_bank),
        .profile_addr              (profile_addr),
        .profile_data              (profile_data[31:0]),
        .profile_commit            (profile_commit),
        .profile_ready             (lane0_profile_ready),
        .active_modulus            (lane0_active_modulus),
        .active_modulus_mu         (lane0_active_mu),
        .busy                      (lane0_busy),
        .done                      (lane0_done),
        .cycles                    (cycles_lane0),
        .multiplication_count      (multiplication_count_lane0),
        .preprocessing_count       (unused_preprocessing_count_lane0),
        .forward_butterfly_count   (unused_forward_count_lane0),
        .pointwise_count           (unused_pointwise_count_lane0),
        .inverse_butterfly_count   (unused_inverse_count_lane0),
        .postprocessing_count      (unused_postprocessing_count_lane0)
    );

    poly_mul4096_four_butterfly_pipeline_runtime_profile_handoff_core lane1 (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .start                     (start),
        .load_a_we                 (load_a_we),
        .load_a_addr               (load_a_addr),
        .load_a_data               (load_a_data[63:32]),
        .load_b_we                 (load_b_we),
        .load_b_addr               (load_b_addr),
        .load_b_data               (load_b_data[63:32]),
        .read_a_addr               (read_a_addr),
        .read_a_data               (lane1_read_a_data),
        .read_b_addr               (read_b_addr),
        .read_b_data               (lane1_read_b_data),
        .handoff_read_valid        (handoff_read_valid),
        .handoff_read_base         (handoff_read_base),
        .handoff_read_data_valid   (lane1_handoff_read_data_valid),
        .handoff_read_data         (lane1_handoff_read_data),
        .handoff_write_valid       (handoff_write_valid),
        .handoff_write_base        (handoff_write_base),
        .handoff_write_a_data      (lane1_handoff_write_a_data),
        .handoff_write_b_data      (lane1_handoff_write_b_data),
        .profile_modulus_we        (profile_modulus_we),
        .profile_modulus_data      (profile_modulus_data[63:32]),
        .profile_modulus_mu_data   (profile_modulus_mu_data[61:31]),
        .profile_we                (profile_we),
        .profile_bank              (profile_bank),
        .profile_addr              (profile_addr),
        .profile_data              (profile_data[63:32]),
        .profile_commit            (profile_commit),
        .profile_ready             (lane1_profile_ready),
        .active_modulus            (lane1_active_modulus),
        .active_modulus_mu         (lane1_active_mu),
        .busy                      (lane1_busy),
        .done                      (lane1_done),
        .cycles                    (cycles_lane1),
        .multiplication_count      (multiplication_count_lane1),
        .preprocessing_count       (unused_preprocessing_count_lane1),
        .forward_butterfly_count   (unused_forward_count_lane1),
        .pointwise_count           (unused_pointwise_count_lane1),
        .inverse_butterfly_count   (unused_inverse_count_lane1),
        .postprocessing_count      (unused_postprocessing_count_lane1)
    );

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (reset_n)
        begin
            if (
                lane0_busy != lane1_busy
                || lane0_done != lane1_done
                || lane0_handoff_read_data_valid
                    != lane1_handoff_read_data_valid
            )
            begin
                $display("ERROR: buffered RNS towers left lockstep");
                $fatal(1);
            end
        end
    end

`endif

endmodule
