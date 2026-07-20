`timescale 1ns/1ps

module ntt4096_profile_bram_four_read (
    input  logic              clk,

    input  logic              write_enable,
    input  logic [11:0]       write_address,
    input  logic [31:0]       write_data,

    input  logic              read_enable,
    input  logic [3:0][11:0]  read_address,
    output logic [3:0][31:0]  read_data
);

    ntt4096_profile_bram_dual_read copy01 (
        .clk            (clk),

        .write_enable   (write_enable),
        .write_address  (write_address),
        .write_data     (write_data),

        .read_enable_a  (read_enable),
        .read_address_a (read_address[0]),
        .read_data_a    (read_data[0]),

        .read_enable_b  (read_enable),
        .read_address_b (read_address[1]),
        .read_data_b    (read_data[1])
    );

    ntt4096_profile_bram_dual_read copy23 (
        .clk            (clk),

        .write_enable   (write_enable),
        .write_address  (write_address),
        .write_data     (write_data),

        .read_enable_a  (read_enable),
        .read_address_a (read_address[2]),
        .read_data_a    (read_data[2]),

        .read_enable_b  (read_enable),
        .read_address_b (read_address[3]),
        .read_data_b    (read_data[3])
    );

endmodule
