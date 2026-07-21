`timescale 1ns/1ps

/* Four-bank 4096 x 64 shadow/result store for four-wide handoff groups. */
module ntt4096_four_bank_coeff_store_runtime64 (
    input  logic              clk,

    input  logic              load_we,
    input  logic [11:0]       load_addr,
    input  logic [63:0]       load_data,

    input  logic              read_valid,
    input  logic [3:0][11:0]  read_addr,
    output logic              read_data_valid,
    output logic [3:0][63:0]  read_data,

    input  logic              write_valid,
    input  logic [3:0][11:0]  write_addr,
    input  logic [3:0][63:0]  write_data
);

    logic [3:0]       bank_read_en;
    logic [3:0][9:0] bank_read_addr;
    logic [3:0][63:0] bank_read_data;

    logic [3:0]       bank_write_en;
    logic [3:0][9:0] bank_write_addr;
    logic [3:0][63:0] bank_write_data;

    logic [3:0][1:0] read_bank_d;
    logic            read_valid_d;

    integer lane;

    function automatic logic [1:0] bank_of (
        input logic [11:0] logical_address
    );
        begin
            bank_of =
                logical_address[1:0];
        end
    endfunction

    function automatic logic [9:0] row_of (
        input logic [11:0] logical_address
    );
        begin
            row_of =
                logical_address[11:2];
        end
    endfunction

    always_comb
    begin
        bank_read_en =
            4'd0;

        bank_read_addr =
            '0;

        bank_write_en =
            4'd0;

        bank_write_addr =
            '0;

        bank_write_data =
            '0;

        for (
            lane = 0;
            lane < 4;
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
        else if (write_valid)
        begin
            for (
                lane = 0;
                lane < 4;
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
            read_valid;

        for (
            lane = 0;
            lane < 4;
            lane = lane + 1
        )
        begin
            read_bank_d[lane] <=
                bank_of(read_addr[lane]);
        end
    end

    always_comb
    begin
        read_data_valid =
            read_valid_d;

        for (
            lane = 0;
            lane < 4;
            lane = lane + 1
        )
        begin
            read_data[lane] =
                bank_read_data[
                    read_bank_d[lane]
                ];
        end
    end

    generate
        genvar bank_index;

        for (
            bank_index = 0;
            bank_index < 4;
            bank_index = bank_index + 1
        )
        begin : banks
            ntt4096_coeff_bank_1024x64 bank (
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
        if (load_we && write_valid)
        begin
            $display(
                "ERROR: 64-bit store scalar load and four-wide write overlap"
            );

            $fatal(1);
        end
    end

`endif

endmodule
