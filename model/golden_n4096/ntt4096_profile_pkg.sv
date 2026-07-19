`timescale 1ns/1ps

package ntt4096_profile_pkg;

    localparam int unsigned NTT_N =
        4096;

    localparam int unsigned NTT_LOG_N =
        12;

    localparam int unsigned NTT_ADDRESS_WIDTH =
        12;

    localparam logic [31:0] NTT_Q =
        32'd1073692673;

    localparam logic [31:0] NTT_SOURCE_ROOT =
        32'd236231;

    localparam logic [31:0] NTT_PSI =
        32'd236231;

    localparam logic [31:0] NTT_OMEGA =
        32'd1046759038;

    localparam logic [31:0] NTT_PSI_INVERSE =
        32'd489520520;

    localparam logic [31:0] NTT_OMEGA_INVERSE =
        32'd59856447;

    localparam logic [31:0] NTT_N_INVERSE =
        32'd1073430541;

    localparam int unsigned NTT_COMPACT_TWIDDLE_WORDS =
        4095;

    localparam int unsigned NTT_BUTTERFLIES_PER_TRANSFORM =
        24576;

    localparam int unsigned NTT_MODULAR_MULTIPLICATIONS_PER_FORWARD =
        28672;

    localparam int unsigned NTT_MODULAR_MULTIPLICATIONS_PER_INVERSE =
        28672;

    localparam int unsigned NTT_MODULAR_MULTIPLICATIONS_PER_PRODUCT =
        90112;

endpackage
