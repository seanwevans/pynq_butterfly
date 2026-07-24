`timescale 1ns/1ps

/*
 * Verilog-2001 AXI4-Stream module-reference top for the all-pair EvalMul3
 * sequencer. The sequencer and arithmetic datapath remain SystemVerilog.
 */
module evalmul3_two_tower_axis_dma_wrapper (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
    input  wire        aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input  wire        aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [63:0] s_axis_tdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TKEEP" *)
    input  wire [7:0]  s_axis_tkeep,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire        s_axis_tvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire        s_axis_tready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
    input  wire        s_axis_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [63:0] m_axis_tdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [7:0]  m_axis_tkeep,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire        m_axis_tvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire        m_axis_tready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire        m_axis_tlast
);

    wire        sequencer_s_axis_tready;
    wire        full_input_word;

    wire        protocol_error;
    wire        profile_ready;
    wire        accelerator_busy;
    wire [63:0] active_modulus;
    wire [61:0] active_modulus_mu;
    wire [31:0] active_batch_size;
    wire [31:0] completed_profiles;
    wire [31:0] completed_ciphertexts;
    wire [31:0] completed_batches;
    wire [31:0] launched_coefficients;

    assign full_input_word =
        &s_axis_tkeep;

    assign s_axis_tready =
        sequencer_s_axis_tready
        && full_input_word;

    assign m_axis_tkeep =
        8'hff;

    evalmul3_all_tower_axis_core #(
        .N              (4096),
        .FIFO_DEPTH     (8),
        .MAX_PAIR_COUNT (6)
    ) core (
        .clk                   (aclk),
        .reset_n               (aresetn),

        .s_axis_tdata          (s_axis_tdata),
        .s_axis_tvalid         (
            s_axis_tvalid
            && full_input_word
        ),
        .s_axis_tready         (sequencer_s_axis_tready),
        .s_axis_tlast          (s_axis_tlast),

        .m_axis_tdata          (m_axis_tdata),
        .m_axis_tvalid         (m_axis_tvalid),
        .m_axis_tready         (m_axis_tready),
        .m_axis_tlast          (m_axis_tlast),

        .protocol_error        (protocol_error),
        .profile_ready         (profile_ready),
        .accelerator_busy      (accelerator_busy),

        .active_modulus        (active_modulus),
        .active_modulus_mu     (active_modulus_mu),

        .active_batch_size     (active_batch_size),
        .completed_profiles    (completed_profiles),
        .completed_ciphertexts (completed_ciphertexts),
        .completed_batches     (completed_batches),
        .launched_coefficients (launched_coefficients)
    );

endmodule
