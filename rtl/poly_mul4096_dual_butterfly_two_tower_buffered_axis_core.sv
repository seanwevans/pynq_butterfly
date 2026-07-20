`timescale 1ns/1ps

/*
 * Two lockstep RNS towers using operand prefetch and a decoupled result buffer.
 * Each 64-bit stream word carries lane 0 in bits 31:0 and lane 1 in
 * bits 63:32.
 */
module poly_mul4096_dual_butterfly_two_tower_buffered_axis_core (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [63:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output logic [63:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,

    output logic        protocol_error,
    output logic        profile_ready,

    output logic [31:0] active_modulus_lane0,
    output logic [31:0] active_modulus_lane1,

    output logic [31:0] completed_profiles,
    output logic [31:0] completed_products,
    output logic [31:0] completed_batches,
    output logic [31:0] completed_prefetches,
    output logic [31:0] completed_refills,
    output logic [31:0] completed_handoffs,
    output logic [31:0] last_handoff_cycles,
    output logic        compute_output_overlap_observed,

    output logic        accelerator_busy,

    output logic [31:0] core_cycles_lane0,
    output logic [31:0] core_cycles_lane1,

    output logic [16:0] modular_multiplications_lane0,
    output logic [16:0] modular_multiplications_lane1
);

    logic lane0_s_ready;
    logic lane1_s_ready;
    logic lane0_s_valid;
    logic lane1_s_valid;

    logic [31:0] lane0_m_data;
    logic [31:0] lane1_m_data;
    logic lane0_m_valid;
    logic lane1_m_valid;
    logic lane0_m_ready;
    logic lane1_m_ready;
    logic lane0_m_last;
    logic lane1_m_last;

    logic lane0_protocol_error;
    logic lane1_protocol_error;
    logic lane0_profile_ready;
    logic lane1_profile_ready;

    logic [31:0] lane0_completed_profiles;
    logic [31:0] lane1_completed_profiles;
    logic [31:0] lane0_completed_products;
    logic [31:0] lane1_completed_products;
    logic [31:0] lane0_completed_batches;
    logic [31:0] lane1_completed_batches;
    logic [31:0] lane0_completed_prefetches;
    logic [31:0] lane1_completed_prefetches;
    logic [31:0] lane0_completed_refills;
    logic [31:0] lane1_completed_refills;
    logic [31:0] lane0_completed_handoffs;
    logic [31:0] lane1_completed_handoffs;
    logic [31:0] lane0_last_handoff_cycles;
    logic [31:0] lane1_last_handoff_cycles;
    logic lane0_overlap_observed;
    logic lane1_overlap_observed;

    logic [31:0] lane0_profile_words;
    logic [31:0] lane1_profile_words;
    logic [31:0] lane0_product_words;
    logic [31:0] lane1_product_words;
    logic lane0_busy;
    logic lane1_busy;

    assign lane0_s_valid =
        s_axis_tvalid
        && lane1_s_ready;

    assign lane1_s_valid =
        s_axis_tvalid
        && lane0_s_ready;

    assign s_axis_tready =
        lane0_s_ready
        && lane1_s_ready;

    assign m_axis_tvalid =
        lane0_m_valid
        && lane1_m_valid;

    assign lane0_m_ready =
        m_axis_tready
        && lane1_m_valid;

    assign lane1_m_ready =
        m_axis_tready
        && lane0_m_valid;

    assign m_axis_tdata = {
        lane1_m_data,
        lane0_m_data
    };

    assign m_axis_tlast =
        lane0_m_last
        && lane1_m_last;

    assign protocol_error =
        lane0_protocol_error
        || lane1_protocol_error;

    assign profile_ready =
        lane0_profile_ready
        && lane1_profile_ready;

    assign completed_profiles =
        lane0_completed_profiles;

    assign completed_products =
        lane0_completed_products;

    assign completed_batches =
        lane0_completed_batches;

    assign completed_prefetches =
        lane0_completed_prefetches;

    assign completed_refills =
        lane0_completed_refills;

    assign completed_handoffs =
        lane0_completed_handoffs;

    assign last_handoff_cycles =
        lane0_last_handoff_cycles;

    assign compute_output_overlap_observed =
        lane0_overlap_observed
        && lane1_overlap_observed;

    assign accelerator_busy =
        lane0_busy
        || lane1_busy;

    poly_mul4096_dual_butterfly_runtime_profile_buffered_axis_core lane0 (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .s_axis_tdata              (s_axis_tdata[31:0]),
        .s_axis_tvalid             (lane0_s_valid),
        .s_axis_tready             (lane0_s_ready),
        .s_axis_tlast              (s_axis_tlast),
        .m_axis_tdata              (lane0_m_data),
        .m_axis_tvalid             (lane0_m_valid),
        .m_axis_tready             (lane0_m_ready),
        .m_axis_tlast              (lane0_m_last),
        .protocol_error            (lane0_protocol_error),
        .profile_ready             (lane0_profile_ready),
        .active_modulus            (active_modulus_lane0),
        .completed_profiles        (lane0_completed_profiles),
        .completed_products        (lane0_completed_products),
        .completed_batches         (lane0_completed_batches),
        .completed_prefetches      (lane0_completed_prefetches),
        .completed_refills         (lane0_completed_refills),
        .completed_handoffs        (lane0_completed_handoffs),
        .last_handoff_cycles       (lane0_last_handoff_cycles),
        .compute_output_overlap_observed (lane0_overlap_observed),
        .profile_words_received    (lane0_profile_words),
        .product_words_received    (lane0_product_words),
        .accelerator_busy          (lane0_busy),
        .core_cycles               (core_cycles_lane0),
        .modular_multiplications   (modular_multiplications_lane0)
    );

    poly_mul4096_dual_butterfly_runtime_profile_buffered_axis_core lane1 (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .s_axis_tdata              (s_axis_tdata[63:32]),
        .s_axis_tvalid             (lane1_s_valid),
        .s_axis_tready             (lane1_s_ready),
        .s_axis_tlast              (s_axis_tlast),
        .m_axis_tdata              (lane1_m_data),
        .m_axis_tvalid             (lane1_m_valid),
        .m_axis_tready             (lane1_m_ready),
        .m_axis_tlast              (lane1_m_last),
        .protocol_error            (lane1_protocol_error),
        .profile_ready             (lane1_profile_ready),
        .active_modulus            (active_modulus_lane1),
        .completed_profiles        (lane1_completed_profiles),
        .completed_products        (lane1_completed_products),
        .completed_batches         (lane1_completed_batches),
        .completed_prefetches      (lane1_completed_prefetches),
        .completed_refills         (lane1_completed_refills),
        .completed_handoffs        (lane1_completed_handoffs),
        .last_handoff_cycles       (lane1_last_handoff_cycles),
        .compute_output_overlap_observed (lane1_overlap_observed),
        .profile_words_received    (lane1_profile_words),
        .product_words_received    (lane1_product_words),
        .accelerator_busy          (lane1_busy),
        .core_cycles               (core_cycles_lane1),
        .modular_multiplications   (modular_multiplications_lane1)
    );

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (reset_n)
        begin
            if (
                lane0_completed_profiles
                != lane1_completed_profiles
                || lane0_completed_products
                != lane1_completed_products
                || lane0_completed_batches
                != lane1_completed_batches
                || lane0_completed_prefetches
                != lane1_completed_prefetches
                || lane0_completed_refills
                != lane1_completed_refills
                || lane0_completed_handoffs
                != lane1_completed_handoffs
                || lane0_last_handoff_cycles
                != lane1_last_handoff_cycles
            )
            begin
                $display(
                    "ERROR: buffered RNS lanes left counter lockstep"
                );

                $fatal(1);
            end

            if (lane0_m_valid != lane1_m_valid)
            begin
                $display(
                    "ERROR: buffered result lanes left valid lockstep"
                );

                $fatal(1);
            end

            if (
                lane0_m_valid
                && lane1_m_valid
                && lane0_m_last != lane1_m_last
            )
            begin
                $display(
                    "ERROR: buffered result lanes disagreed on TLAST"
                );

                $fatal(1);
            end

            if (
                lane0_completed_products != 0
                && core_cycles_lane0 != core_cycles_lane1
            )
            begin
                $display(
                    "ERROR: buffered RNS lanes reported different cycles"
                );

                $fatal(1);
            end
        end
    end

`endif

endmodule
