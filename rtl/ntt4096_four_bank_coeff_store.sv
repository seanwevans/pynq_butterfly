`timescale 1ns/1ps

/*
 * Four-bank N=4096 coefficient store.
 *
 * Logical address a[11:0] maps to:
 *
 *   bank[0] = a0 ^ a2 ^ a4 ^ a6 ^ a8 ^ a10
 *   bank[1] = a1 ^ a3 ^ a5 ^ a7 ^ a9 ^ a11
 *   row     = a[11:2]
 *
 * The dual-butterfly scheduler guarantees that each four-address
 * read or write group contains exactly one address for each bank.
 *
 * Each physical bank is isolated in a canonical 1024 x 32
 * simple-dual-port RAM module so Vivado can infer one RAMB36E1.
 */
module ntt4096_four_bank_coeff_store (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        load_we,
    input  logic [11:0] load_addr,
    input  logic [31:0] load_data,

    input  logic        read_valid,
    input  logic [11:0] read_addr0,
    input  logic [11:0] read_addr1,
    input  logic [11:0] read_addr2,
    input  logic [11:0] read_addr3,

    output logic        read_data_valid,
    output logic [31:0] read_data0,
    output logic [31:0] read_data1,
    output logic [31:0] read_data2,
    output logic [31:0] read_data3,

    input  logic        write_valid,
    input  logic [11:0] write_addr0,
    input  logic [11:0] write_addr1,
    input  logic [11:0] write_addr2,
    input  logic [11:0] write_addr3,
    input  logic [31:0] write_data0,
    input  logic [31:0] write_data1,
    input  logic [31:0] write_data2,
    input  logic [31:0] write_data3
);

    function automatic [1:0] logical_bank;
        input [11:0] address;

        begin
            logical_bank[0] =
                address[0]
                ^ address[2]
                ^ address[4]
                ^ address[6]
                ^ address[8]
                ^ address[10];

            logical_bank[1] =
                address[1]
                ^ address[3]
                ^ address[5]
                ^ address[7]
                ^ address[9]
                ^ address[11];
        end
    endfunction

    logic [1:0] read_bank0;
    logic [1:0] read_bank1;
    logic [1:0] read_bank2;
    logic [1:0] read_bank3;

    logic [9:0] bank_read_addr0;
    logic [9:0] bank_read_addr1;
    logic [9:0] bank_read_addr2;
    logic [9:0] bank_read_addr3;

    logic [1:0] bank_read_owner0;
    logic [1:0] bank_read_owner1;
    logic [1:0] bank_read_owner2;
    logic [1:0] bank_read_owner3;

    logic [1:0] bank_read_owner0_q;
    logic [1:0] bank_read_owner1_q;
    logic [1:0] bank_read_owner2_q;
    logic [1:0] bank_read_owner3_q;

    logic [31:0] bank_read_data0;
    logic [31:0] bank_read_data1;
    logic [31:0] bank_read_data2;
    logic [31:0] bank_read_data3;

    logic bank_write_en0;
    logic bank_write_en1;
    logic bank_write_en2;
    logic bank_write_en3;

    logic [9:0] bank_write_addr0;
    logic [9:0] bank_write_addr1;
    logic [9:0] bank_write_addr2;
    logic [9:0] bank_write_addr3;

    logic [31:0] bank_write_data0;
    logic [31:0] bank_write_data1;
    logic [31:0] bank_write_data2;
    logic [31:0] bank_write_data3;

    assign read_bank0 =
        logical_bank(read_addr0);

    assign read_bank1 =
        logical_bank(read_addr1);

    assign read_bank2 =
        logical_bank(read_addr2);

    assign read_bank3 =
        logical_bank(read_addr3);

    always @*
    begin
        bank_read_addr0 =
            10'd0;

        bank_read_addr1 =
            10'd0;

        bank_read_addr2 =
            10'd0;

        bank_read_addr3 =
            10'd0;

        bank_read_owner0 =
            2'd0;

        bank_read_owner1 =
            2'd0;

        bank_read_owner2 =
            2'd0;

        bank_read_owner3 =
            2'd0;

        case (read_bank0)
            2'd0:
            begin
                bank_read_addr0 =
                    read_addr0[11:2];

                bank_read_owner0 =
                    2'd0;
            end

            2'd1:
            begin
                bank_read_addr1 =
                    read_addr0[11:2];

                bank_read_owner1 =
                    2'd0;
            end

            2'd2:
            begin
                bank_read_addr2 =
                    read_addr0[11:2];

                bank_read_owner2 =
                    2'd0;
            end

            default:
            begin
                bank_read_addr3 =
                    read_addr0[11:2];

                bank_read_owner3 =
                    2'd0;
            end
        endcase

        case (read_bank1)
            2'd0:
            begin
                bank_read_addr0 =
                    read_addr1[11:2];

                bank_read_owner0 =
                    2'd1;
            end

            2'd1:
            begin
                bank_read_addr1 =
                    read_addr1[11:2];

                bank_read_owner1 =
                    2'd1;
            end

            2'd2:
            begin
                bank_read_addr2 =
                    read_addr1[11:2];

                bank_read_owner2 =
                    2'd1;
            end

            default:
            begin
                bank_read_addr3 =
                    read_addr1[11:2];

                bank_read_owner3 =
                    2'd1;
            end
        endcase

        case (read_bank2)
            2'd0:
            begin
                bank_read_addr0 =
                    read_addr2[11:2];

                bank_read_owner0 =
                    2'd2;
            end

            2'd1:
            begin
                bank_read_addr1 =
                    read_addr2[11:2];

                bank_read_owner1 =
                    2'd2;
            end

            2'd2:
            begin
                bank_read_addr2 =
                    read_addr2[11:2];

                bank_read_owner2 =
                    2'd2;
            end

            default:
            begin
                bank_read_addr3 =
                    read_addr2[11:2];

                bank_read_owner3 =
                    2'd2;
            end
        endcase

        case (read_bank3)
            2'd0:
            begin
                bank_read_addr0 =
                    read_addr3[11:2];

                bank_read_owner0 =
                    2'd3;
            end

            2'd1:
            begin
                bank_read_addr1 =
                    read_addr3[11:2];

                bank_read_owner1 =
                    2'd3;
            end

            2'd2:
            begin
                bank_read_addr2 =
                    read_addr3[11:2];

                bank_read_owner2 =
                    2'd3;
            end

            default:
            begin
                bank_read_addr3 =
                    read_addr3[11:2];

                bank_read_owner3 =
                    2'd3;
            end
        endcase
    end

    always @*
    begin
        bank_write_en0 =
            1'b0;

        bank_write_en1 =
            1'b0;

        bank_write_en2 =
            1'b0;

        bank_write_en3 =
            1'b0;

        bank_write_addr0 =
            10'd0;

        bank_write_addr1 =
            10'd0;

        bank_write_addr2 =
            10'd0;

        bank_write_addr3 =
            10'd0;

        bank_write_data0 =
            32'd0;

        bank_write_data1 =
            32'd0;

        bank_write_data2 =
            32'd0;

        bank_write_data3 =
            32'd0;

        if (load_we)
        begin
            case (logical_bank(load_addr))
                2'd0:
                begin
                    bank_write_en0 =
                        1'b1;

                    bank_write_addr0 =
                        load_addr[11:2];

                    bank_write_data0 =
                        load_data;
                end

                2'd1:
                begin
                    bank_write_en1 =
                        1'b1;

                    bank_write_addr1 =
                        load_addr[11:2];

                    bank_write_data1 =
                        load_data;
                end

                2'd2:
                begin
                    bank_write_en2 =
                        1'b1;

                    bank_write_addr2 =
                        load_addr[11:2];

                    bank_write_data2 =
                        load_data;
                end

                default:
                begin
                    bank_write_en3 =
                        1'b1;

                    bank_write_addr3 =
                        load_addr[11:2];

                    bank_write_data3 =
                        load_data;
                end
            endcase
        end
        else if (write_valid)
        begin
            case (logical_bank(write_addr0))
                2'd0:
                begin
                    bank_write_en0 =
                        1'b1;

                    bank_write_addr0 =
                        write_addr0[11:2];

                    bank_write_data0 =
                        write_data0;
                end

                2'd1:
                begin
                    bank_write_en1 =
                        1'b1;

                    bank_write_addr1 =
                        write_addr0[11:2];

                    bank_write_data1 =
                        write_data0;
                end

                2'd2:
                begin
                    bank_write_en2 =
                        1'b1;

                    bank_write_addr2 =
                        write_addr0[11:2];

                    bank_write_data2 =
                        write_data0;
                end

                default:
                begin
                    bank_write_en3 =
                        1'b1;

                    bank_write_addr3 =
                        write_addr0[11:2];

                    bank_write_data3 =
                        write_data0;
                end
            endcase

            case (logical_bank(write_addr1))
                2'd0:
                begin
                    bank_write_en0 =
                        1'b1;

                    bank_write_addr0 =
                        write_addr1[11:2];

                    bank_write_data0 =
                        write_data1;
                end

                2'd1:
                begin
                    bank_write_en1 =
                        1'b1;

                    bank_write_addr1 =
                        write_addr1[11:2];

                    bank_write_data1 =
                        write_data1;
                end

                2'd2:
                begin
                    bank_write_en2 =
                        1'b1;

                    bank_write_addr2 =
                        write_addr1[11:2];

                    bank_write_data2 =
                        write_data1;
                end

                default:
                begin
                    bank_write_en3 =
                        1'b1;

                    bank_write_addr3 =
                        write_addr1[11:2];

                    bank_write_data3 =
                        write_data1;
                end
            endcase

            case (logical_bank(write_addr2))
                2'd0:
                begin
                    bank_write_en0 =
                        1'b1;

                    bank_write_addr0 =
                        write_addr2[11:2];

                    bank_write_data0 =
                        write_data2;
                end

                2'd1:
                begin
                    bank_write_en1 =
                        1'b1;

                    bank_write_addr1 =
                        write_addr2[11:2];

                    bank_write_data1 =
                        write_data2;
                end

                2'd2:
                begin
                    bank_write_en2 =
                        1'b1;

                    bank_write_addr2 =
                        write_addr2[11:2];

                    bank_write_data2 =
                        write_data2;
                end

                default:
                begin
                    bank_write_en3 =
                        1'b1;

                    bank_write_addr3 =
                        write_addr2[11:2];

                    bank_write_data3 =
                        write_data2;
                end
            endcase

            case (logical_bank(write_addr3))
                2'd0:
                begin
                    bank_write_en0 =
                        1'b1;

                    bank_write_addr0 =
                        write_addr3[11:2];

                    bank_write_data0 =
                        write_data3;
                end

                2'd1:
                begin
                    bank_write_en1 =
                        1'b1;

                    bank_write_addr1 =
                        write_addr3[11:2];

                    bank_write_data1 =
                        write_data3;
                end

                2'd2:
                begin
                    bank_write_en2 =
                        1'b1;

                    bank_write_addr2 =
                        write_addr3[11:2];

                    bank_write_data2 =
                        write_data3;
                end

                default:
                begin
                    bank_write_en3 =
                        1'b1;

                    bank_write_addr3 =
                        write_addr3[11:2];

                    bank_write_data3 =
                        write_data3;
                end
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            read_data_valid <=
                1'b0;

            bank_read_owner0_q <=
                2'd0;

            bank_read_owner1_q <=
                2'd0;

            bank_read_owner2_q <=
                2'd0;

            bank_read_owner3_q <=
                2'd0;
        end
        else
        begin
            read_data_valid <=
                read_valid;

            if (read_valid)
            begin
                bank_read_owner0_q <=
                    bank_read_owner0;

                bank_read_owner1_q <=
                    bank_read_owner1;

                bank_read_owner2_q <=
                    bank_read_owner2;

                bank_read_owner3_q <=
                    bank_read_owner3;
            end
        end
    end

    always @*
    begin
        read_data0 =
            32'd0;

        read_data1 =
            32'd0;

        read_data2 =
            32'd0;

        read_data3 =
            32'd0;

        case (bank_read_owner0_q)
            2'd0:
                read_data0 =
                    bank_read_data0;

            2'd1:
                read_data1 =
                    bank_read_data0;

            2'd2:
                read_data2 =
                    bank_read_data0;

            default:
                read_data3 =
                    bank_read_data0;
        endcase

        case (bank_read_owner1_q)
            2'd0:
                read_data0 =
                    bank_read_data1;

            2'd1:
                read_data1 =
                    bank_read_data1;

            2'd2:
                read_data2 =
                    bank_read_data1;

            default:
                read_data3 =
                    bank_read_data1;
        endcase

        case (bank_read_owner2_q)
            2'd0:
                read_data0 =
                    bank_read_data2;

            2'd1:
                read_data1 =
                    bank_read_data2;

            2'd2:
                read_data2 =
                    bank_read_data2;

            default:
                read_data3 =
                    bank_read_data2;
        endcase

        case (bank_read_owner3_q)
            2'd0:
                read_data0 =
                    bank_read_data3;

            2'd1:
                read_data1 =
                    bank_read_data3;

            2'd2:
                read_data2 =
                    bank_read_data3;

            default:
                read_data3 =
                    bank_read_data3;
        endcase
    end

    ntt4096_coeff_bank_1024x32 bank0 (
        .clk        (clk),

        .read_en    (read_valid),
        .read_addr  (bank_read_addr0),
        .read_data  (bank_read_data0),

        .write_en   (bank_write_en0),
        .write_addr (bank_write_addr0),
        .write_data (bank_write_data0)
    );

    ntt4096_coeff_bank_1024x32 bank1 (
        .clk        (clk),

        .read_en    (read_valid),
        .read_addr  (bank_read_addr1),
        .read_data  (bank_read_data1),

        .write_en   (bank_write_en1),
        .write_addr (bank_write_addr1),
        .write_data (bank_write_data1)
    );

    ntt4096_coeff_bank_1024x32 bank2 (
        .clk        (clk),

        .read_en    (read_valid),
        .read_addr  (bank_read_addr2),
        .read_data  (bank_read_data2),

        .write_en   (bank_write_en2),
        .write_addr (bank_write_addr2),
        .write_data (bank_write_data2)
    );

    ntt4096_coeff_bank_1024x32 bank3 (
        .clk        (clk),

        .read_en    (read_valid),
        .read_addr  (bank_read_addr3),
        .read_data  (bank_read_data3),

        .write_en   (bank_write_en3),
        .write_addr (bank_write_addr3),
        .write_data (bank_write_data3)
    );

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            reset_n
            && read_valid
        )
        begin
            if (
                read_bank0 == read_bank1
                || read_bank0 == read_bank2
                || read_bank0 == read_bank3
                || read_bank1 == read_bank2
                || read_bank1 == read_bank3
                || read_bank2 == read_bank3
            )
            begin
                $display(
                    "ERROR: four-bank coefficient-store read conflict"
                );

                $fatal(1);
            end
        end

        if (
            reset_n
            && write_valid
            && !load_we
        )
        begin
            if (
                logical_bank(write_addr0) == logical_bank(write_addr1)
                || logical_bank(write_addr0) == logical_bank(write_addr2)
                || logical_bank(write_addr0) == logical_bank(write_addr3)
                || logical_bank(write_addr1) == logical_bank(write_addr2)
                || logical_bank(write_addr1) == logical_bank(write_addr3)
                || logical_bank(write_addr2) == logical_bank(write_addr3)
            )
            begin
                $display(
                    "ERROR: four-bank coefficient-store write conflict"
                );

                $fatal(1);
            end
        end
    end

`endif

endmodule
