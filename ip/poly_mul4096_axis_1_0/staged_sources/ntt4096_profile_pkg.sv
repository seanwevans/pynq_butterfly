`timescale 1ns/1ps

package ntt4096_profile_pkg;

    localparam integer NTT_N =
        4096;

    localparam integer NTT_LOG_N =
        12;

    localparam integer NTT_ADDRESS_WIDTH =
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

    localparam integer NTT_COMPACT_TWIDDLE_WORDS =
        4095;

    localparam integer NTT_BUTTERFLIES_PER_TRANSFORM =
        24576;

    localparam integer NTT_MODULAR_MULTIPLICATIONS_PER_FORWARD =
        28672;

    localparam integer NTT_MODULAR_MULTIPLICATIONS_PER_INVERSE =
        28672;

    localparam integer NTT_MODULAR_MULTIPLICATIONS_PER_PRODUCT =
        90112;

endpackage
