`timescale 1ns/1ps

/*
 * Physical co-residency shell for the two exact arithmetic engines required
 * by fused OpenFHE BV relinearization:
 *
 *     EvalMultNoRelin:
 *         c0 = a0*b0
 *         c1 = a0*b1 + a1*b0
 *         c2 = a1*b1
 *
 *     BV key-switch MAC:
 *         ks_b = sum_j digit_j * eval_key_b_j
 *         ks_a = sum_j digit_j * eval_key_a_j
 *
 * The engines intentionally retain independent AXI4-Stream interfaces in this
 * checkpoint. The goal is to measure whether the complete 192-DSP arithmetic
 * population places and routes together at 100 MHz before adding the fused
 * sequencer, c0/c1 alignment FIFOs, and final modular additions.
 */
module evalmul3_bv_mac_coresidency_top #(
    parameter integer N = 4096,
    parameter integer EVALMUL_FIFO_DEPTH = 8,
    parameter integer BV_MAX_DIGITS = 16,
    parameter integer BV_FIFO_DEPTH = 8
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [63:0] evalmul_s_axis_tdata,
    input  logic        evalmul_s_axis_tvalid,
    output logic        evalmul_s_axis_tready,
    input  logic        evalmul_s_axis_tlast,

    output logic [63:0] evalmul_m_axis_tdata,
    output logic        evalmul_m_axis_tvalid,
    input  logic        evalmul_m_axis_tready,
    output logic        evalmul_m_axis_tlast,

    input  logic [63:0] bv_s_axis_tdata,
    input  logic        bv_s_axis_tvalid,
    output logic        bv_s_axis_tready,
    input  logic        bv_s_axis_tlast,

    output logic [63:0] bv_m_axis_tdata,
    output logic        bv_m_axis_tvalid,
    input  logic        bv_m_axis_tready,
    output logic        bv_m_axis_tlast,

    output logic        evalmul_protocol_error,
    output logic        evalmul_profile_ready,
    output logic        evalmul_busy,

    output logic        bv_protocol_error,
    output logic        bv_profile_ready,
    output logic        bv_busy,

    output logic [31:0] evalmul_completed_batches,
    output logic [31:0] bv_completed_batches,

    output logic [31:0] evalmul_launched_coefficients,
    output logic [31:0] bv_launched_digit_products
);

    (* KEEP_HIERARCHY = "yes" *)
    evalmul3_two_tower_axis_core #(
        .N          (N),
        .FIFO_DEPTH (EVALMUL_FIFO_DEPTH)
    ) evalmul_engine (
        .clk                   (clk),
        .reset_n               (reset_n),

        .s_axis_tdata          (evalmul_s_axis_tdata),
        .s_axis_tvalid         (evalmul_s_axis_tvalid),
        .s_axis_tready         (evalmul_s_axis_tready),
        .s_axis_tlast          (evalmul_s_axis_tlast),

        .m_axis_tdata          (evalmul_m_axis_tdata),
        .m_axis_tvalid         (evalmul_m_axis_tvalid),
        .m_axis_tready         (evalmul_m_axis_tready),
        .m_axis_tlast          (evalmul_m_axis_tlast),

        .protocol_error        (evalmul_protocol_error),
        .profile_ready         (evalmul_profile_ready),
        .accelerator_busy      (evalmul_busy),

        .active_modulus        (),
        .active_modulus_mu     (),

        .active_batch_size     (),
        .completed_profiles    (),
        .completed_ciphertexts (),
        .completed_batches     (evalmul_completed_batches),
        .launched_coefficients (evalmul_launched_coefficients)
    );

    (* KEEP_HIERARCHY = "yes" *)
    bv_keyswitch_mac_two_tower_axis_core #(
        .N          (N),
        .MAX_DIGITS (BV_MAX_DIGITS),
        .FIFO_DEPTH (BV_FIFO_DEPTH)
    ) bv_mac_engine (
        .clk                     (clk),
        .reset_n                 (reset_n),

        .s_axis_tdata            (bv_s_axis_tdata),
        .s_axis_tvalid           (bv_s_axis_tvalid),
        .s_axis_tready           (bv_s_axis_tready),
        .s_axis_tlast            (bv_s_axis_tlast),

        .m_axis_tdata            (bv_m_axis_tdata),
        .m_axis_tvalid           (bv_m_axis_tvalid),
        .m_axis_tready           (bv_m_axis_tready),
        .m_axis_tlast            (bv_m_axis_tlast),

        .protocol_error          (bv_protocol_error),
        .profile_ready           (bv_profile_ready),
        .accelerator_busy        (bv_busy),

        .active_modulus          (),
        .active_modulus_mu       (),

        .active_batch_size       (),
        .active_digit_count      (),
        .completed_profiles      (),
        .completed_ciphertexts   (),
        .completed_batches       (bv_completed_batches),
        .launched_digit_products (bv_launched_digit_products),
        .completed_coefficients  ()
    );

endmodule
