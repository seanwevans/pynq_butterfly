package ntt256_profile_pkg;

    localparam integer NTT_N = 256;
    localparam integer NTT_LOG_N = 8;
    localparam integer NTT_ADDRESS_WIDTH = 8;
    localparam integer NTT_TWIDDLE_WORDS = 255;
    localparam integer NTT_TWIDDLE_ADDRESS_WIDTH = 8;
    localparam integer NTT_BUTTERFLIES = 1024;

    localparam logic [31:0] NTT_Q =
        32'd1073692673;

    localparam logic [31:0] NTT_PSI =
        32'd380625147;

    localparam logic [31:0] NTT_OMEGA =
        32'd628150263;

    localparam logic [31:0] NTT_PSI_INVERSE =
        32'd38973572;

    localparam logic [31:0] NTT_OMEGA_INVERSE =
        32'd247950833;

    localparam logic [31:0] NTT_N_INVERSE =
        32'd1069498561;

endpackage
