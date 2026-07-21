`timescale 1ns/1ps

module ntt4096_four_butterfly_transform_synthesis_top (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        modulus_we,
    input  logic [31:0] modulus_data,

    input  logic        twiddle_we,
    input  logic [11:0] twiddle_addr,
    input  logic [31:0] twiddle_data,

    input  logic        load_we,
    input  logic [11:0] load_addr,
    input  logic [31:0] load_data,

    input  logic [11:0] read_addr,

    input  logic        start,
    input  logic        inverse_mode,

    output logic [31:0] read_data,
    output logic        busy,
    output logic        done,
    output logic [31:0] cycles,
    output logic [14:0] butterfly_count
);

    logic        reset_n_q;

    logic        modulus_we_q;
    logic [31:0] modulus_data_q;

    logic        twiddle_we_q;
    logic [11:0] twiddle_addr_q;
    logic [31:0] twiddle_data_q;

    logic        load_we_q;
    logic [11:0] load_addr_q;
    logic [31:0] load_data_q;

    logic [11:0] read_addr_q;

    logic        start_q;
    logic        inverse_mode_q;

    logic [31:0] inner_read_data;
    logic        inner_busy;
    logic        inner_done;
    logic [31:0] inner_cycles;
    logic [14:0] inner_butterfly_count;

    always_ff @(posedge clk)
    begin
        reset_n_q <=
            reset_n;

        modulus_we_q <=
            modulus_we;

        modulus_data_q <=
            modulus_data;

        twiddle_we_q <=
            twiddle_we;

        twiddle_addr_q <=
            twiddle_addr;

        twiddle_data_q <=
            twiddle_data;

        load_we_q <=
            load_we;

        load_addr_q <=
            load_addr;

        load_data_q <=
            load_data;

        read_addr_q <=
            read_addr;

        start_q <=
            start;

        inverse_mode_q <=
            inverse_mode;

        read_data <=
            inner_read_data;

        busy <=
            inner_busy;

        done <=
            inner_done;

        cycles <=
            inner_cycles;

        butterfly_count <=
            inner_butterfly_count;
    end

    ntt4096_four_butterfly_transform_core core (
        .clk (
            clk
        ),

        .reset_n (
            reset_n_q
        ),

        .modulus_we (
            modulus_we_q
        ),

        .modulus_data (
            modulus_data_q
        ),

        .twiddle_we (
            twiddle_we_q
        ),

        .twiddle_addr (
            twiddle_addr_q
        ),

        .twiddle_data (
            twiddle_data_q
        ),

        .load_we (
            load_we_q
        ),

        .load_addr (
            load_addr_q
        ),

        .load_data (
            load_data_q
        ),

        .read_addr (
            read_addr_q
        ),

        .read_data (
            inner_read_data
        ),

        .start (
            start_q
        ),

        .inverse_mode (
            inverse_mode_q
        ),

        .busy (
            inner_busy
        ),

        .done (
            inner_done
        ),

        .cycles (
            inner_cycles
        ),

        .butterfly_count (
            inner_butterfly_count
        )
    );

endmodule
