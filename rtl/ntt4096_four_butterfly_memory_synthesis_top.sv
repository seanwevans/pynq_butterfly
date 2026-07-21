module ntt4096_four_butterfly_memory_synthesis_top (
    input  logic             clk,

    input  logic [3:0]       stage,
    input  logic [8:0]       group_index,

    input  logic             write_valid,
    input  logic [7:0][31:0] write_data,

    input  logic             read_valid,

    output logic             read_data_valid,
    output logic [7:0][31:0] read_data,
    output logic [7:0][11:0] logical_address
);

    logic [3:0]       stage_q;
    logic [8:0]       group_index_q;

    logic             write_valid_q;
    logic [7:0][31:0] write_data_q;

    logic             read_valid_q;

    logic             inner_read_data_valid;
    logic [7:0][31:0] inner_read_data;
    logic [7:0][11:0] inner_logical_address;

    always_ff @(posedge clk)
    begin
        stage_q <=
            stage;

        group_index_q <=
            group_index;

        write_valid_q <=
            write_valid;

        write_data_q <=
            write_data;

        read_valid_q <=
            read_valid;

        read_data_valid <=
            inner_read_data_valid;

        read_data <=
            inner_read_data;

        logical_address <=
            inner_logical_address;
    end

    ntt4096_four_butterfly_memory_checkpoint_top checkpoint (
        .clk (
            clk
        ),

        .stage (
            stage_q
        ),

        .group_index (
            group_index_q
        ),

        .write_valid (
            write_valid_q
        ),

        .write_data (
            write_data_q
        ),

        .read_valid (
            read_valid_q
        ),

        .read_data_valid (
            inner_read_data_valid
        ),

        .read_data (
            inner_read_data
        ),

        .logical_address (
            inner_logical_address
        )
    );

endmodule
