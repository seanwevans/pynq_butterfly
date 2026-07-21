`timescale 1ns/1ps

/*
 * Eight-bank arithmetic coefficient store with a dedicated four-wide,
 * idle-only handoff read/write port.
 *
 * The four-wide handoff read must not be expressed as an ordinary eight-wide
 * read beginning at an arbitrary four-aligned address.  At bases such as 28,
 * addresses base..base+7 cross the XOR-bank permutation boundary and collide.
 * The dedicated handoff port requests only base..base+3, which is always
 * conflict-free for a four-aligned base.
 */
module ntt4096_eight_bank_coeff_store_runtime_handoff4 (
    input  logic              clk,

    input  logic              load_we,
    input  logic [11:0]       load_addr,
    input  logic [31:0]       load_data,

    input  logic              read_valid,
    input  logic [7:0][11:0]  read_addr,
    output logic              read_data_valid,
    output logic [7:0][31:0]  read_data,

    input  logic              write_valid,
    input  logic [7:0][11:0]  write_addr,
    input  logic [7:0][31:0]  write_data,

    input  logic              handoff_read_valid,
    input  logic [11:0]       handoff_read_base,
    output logic              handoff_read_data_valid,
    output logic [3:0][31:0]  handoff_read_data,

    input  logic              handoff_write_valid,
    input  logic [11:0]       handoff_write_base,
    input  logic [3:0][31:0]  handoff_write_data
);

    logic [7:0]       bank_read_en;
    logic [7:0][8:0] bank_read_addr;
    logic [7:0][31:0] bank_read_data;

    logic [7:0]       bank_write_en;
    logic [7:0][8:0] bank_write_addr;
    logic [7:0][31:0] bank_write_data;

    logic [7:0][2:0] read_bank_d;
    logic            read_valid_d;

    logic [3:0][2:0] handoff_read_bank_d;
    logic            handoff_read_valid_d;

    logic [3:0][11:0] handoff_read_addr;
    logic [3:0][11:0] handoff_write_addr;

    integer lane;

    function automatic logic [2:0] bank_of (
        input logic [11:0] logical_address
    );
        begin
            bank_of[0] =
                logical_address[0]
                ^ logical_address[3]
                ^ logical_address[6]
                ^ logical_address[9];

            bank_of[1] =
                logical_address[1]
                ^ logical_address[4]
                ^ logical_address[7]
                ^ logical_address[10];

            bank_of[2] =
                logical_address[2]
                ^ logical_address[5]
                ^ logical_address[8]
                ^ logical_address[11];
        end
    endfunction

    function automatic logic [8:0] row_of (
        input logic [11:0] logical_address
    );
        begin
            row_of =
                logical_address[11:3];
        end
    endfunction

    always_comb
    begin
        for (
            lane = 0;
            lane < 4;
            lane = lane + 1
        )
        begin
            handoff_read_addr[lane] =
                handoff_read_base + lane[11:0];

            handoff_write_addr[lane] =
                handoff_write_base + lane[11:0];
        end
    end

    always_comb
    begin
        bank_read_en =
            8'd0;

        bank_read_addr =
            '0;

        bank_write_en =
            8'd0;

        bank_write_addr =
            '0;

        bank_write_data =
            '0;

        if (handoff_read_valid)
        begin
            for (
                lane = 0;
                lane < 4;
                lane = lane + 1
            )
            begin
                bank_read_en[
                    bank_of(handoff_read_addr[lane])
                ] =
                    1'b1;

                bank_read_addr[
                    bank_of(handoff_read_addr[lane])
                ] =
                    row_of(handoff_read_addr[lane]);
            end
        end
        else
        begin
            for (
                lane = 0;
                lane < 8;
                lane = lane + 1
            )
            begin
                if (read_valid)
                begin
                    bank_read_en[
                        bank_of(read_addr[lane])
                    ] =
                        1'b1;

                    bank_read_addr[
                        bank_of(read_addr[lane])
                    ] =
                        row_of(read_addr[lane]);
                end
            end
        end

        if (load_we)
        begin
            bank_write_en[
                bank_of(load_addr)
            ] =
                1'b1;

            bank_write_addr[
                bank_of(load_addr)
            ] =
                row_of(load_addr);

            bank_write_data[
                bank_of(load_addr)
            ] =
                load_data;
        end
        else if (handoff_write_valid)
        begin
            for (
                lane = 0;
                lane < 4;
                lane = lane + 1
            )
            begin
                bank_write_en[
                    bank_of(handoff_write_addr[lane])
                ] =
                    1'b1;

                bank_write_addr[
                    bank_of(handoff_write_addr[lane])
                ] =
                    row_of(handoff_write_addr[lane]);

                bank_write_data[
                    bank_of(handoff_write_addr[lane])
                ] =
                    handoff_write_data[lane];
            end
        end
        else if (write_valid)
        begin
            for (
                lane = 0;
                lane < 8;
                lane = lane + 1
            )
            begin
                bank_write_en[
                    bank_of(write_addr[lane])
                ] =
                    1'b1;

                bank_write_addr[
                    bank_of(write_addr[lane])
                ] =
                    row_of(write_addr[lane]);

                bank_write_data[
                    bank_of(write_addr[lane])
                ] =
                    write_data[lane];
            end
        end
    end

    always_ff @(posedge clk)
    begin
        read_valid_d <=
            read_valid
            && !handoff_read_valid;

        handoff_read_valid_d <=
            handoff_read_valid;

        for (
            lane = 0;
            lane < 8;
            lane = lane + 1
        )
        begin
            read_bank_d[lane] <=
                bank_of(read_addr[lane]);
        end

        for (
            lane = 0;
            lane < 4;
            lane = lane + 1
        )
        begin
            handoff_read_bank_d[lane] <=
                bank_of(handoff_read_addr[lane]);
        end
    end

    always_comb
    begin
        read_data_valid =
            read_valid_d;

        handoff_read_data_valid =
            handoff_read_valid_d;

        for (
            lane = 0;
            lane < 8;
            lane = lane + 1
        )
        begin
            read_data[lane] =
                bank_read_data[
                    read_bank_d[lane]
                ];
        end

        for (
            lane = 0;
            lane < 4;
            lane = lane + 1
        )
        begin
            handoff_read_data[lane] =
                bank_read_data[
                    handoff_read_bank_d[lane]
                ];
        end
    end

    generate
        genvar bank_index;

        for (
            bank_index = 0;
            bank_index < 8;
            bank_index = bank_index + 1
        )
        begin : banks
            ntt4096_coeff_bank_512x32 bank (
                .clk        (clk),
                .read_en    (bank_read_en[bank_index]),
                .read_addr  (bank_read_addr[bank_index]),
                .read_data  (bank_read_data[bank_index]),
                .write_en   (bank_write_en[bank_index]),
                .write_addr (bank_write_addr[bank_index]),
                .write_data (bank_write_data[bank_index])
            );
        end
    endgenerate

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            (load_we && handoff_write_valid)
            || (load_we && write_valid)
            || (handoff_write_valid && write_valid)
        )
        begin
            $display(
                "ERROR: overlapping coefficient-store write sources"
            );

            $fatal(1);
        end
    end

`endif

endmodule
