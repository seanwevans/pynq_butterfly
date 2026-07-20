module ntt4096_four_butterfly_memory_checkpoint_top (
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

    ntt4096_four_butterfly_schedule_core schedule (
        .stage (
            stage
        ),

        .group_index (
            group_index
        ),

        .address (
            logical_address
        )
    );

    ntt4096_eight_bank_coeff_store store (
        .clk (
            clk
        ),

        .read_valid (
            read_valid
        ),

        .read_addr (
            logical_address
        ),

        .read_data_valid (
            read_data_valid
        ),

        .read_data (
            read_data
        ),

        .write_valid (
            write_valid
        ),

        .write_addr (
            logical_address
        ),

        .write_data (
            write_data
        )
    );

endmodule
