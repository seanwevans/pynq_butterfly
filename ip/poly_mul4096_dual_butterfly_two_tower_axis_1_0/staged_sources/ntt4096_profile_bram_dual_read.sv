`timescale 1ns/1ps

/*
 * Runtime-programmable 4096 x 32-bit profile table with two
 * simultaneous synchronous read ports.
 *
 * The earlier generic two-process inference style caused Vivado to
 * duplicate the table, consuming eight RAMB36 blocks. This revision
 * uses one explicit Xilinx true-dual-port XPM memory:
 *
 *   port A: runtime write while idle, or twiddle read 0
 *   port B: twiddle read 1
 *
 * Writes and transform reads are mutually exclusive.
 *
 * Icarus uses the behavioral branch below. Vivado uses the XPM branch.
 */
module ntt4096_profile_bram_dual_read (
    input  logic        clk,

    input  logic        write_enable,
    input  logic [11:0] write_address,
    input  logic [31:0] write_data,

    input  logic        read_enable_a,
    input  logic [11:0] read_address_a,
    output logic [31:0] read_data_a,

    input  logic        read_enable_b,
    input  logic [11:0] read_address_b,
    output logic [31:0] read_data_b
);

`ifdef __ICARUS__

    /*
     * Functional simulation model. The arithmetic core never writes
     * and reads this table in the same cycle.
     */
    logic [31:0] memory [0:4095];

    always_ff @(posedge clk)
    begin
        if (write_enable)
        begin
            memory[write_address] <=
                write_data;
        end
        else if (read_enable_a)
        begin
            read_data_a <=
                memory[read_address_a];
        end

        if (read_enable_b)
        begin
            read_data_b <=
                memory[read_address_b];
        end
    end

`else

    logic [11:0] port_a_address;

    assign port_a_address =
        write_enable
            ? write_address
            : read_address_a;

    xpm_memory_tdpram #(
        .ADDR_WIDTH_A           (12),
        .ADDR_WIDTH_B           (12),
        .AUTO_SLEEP_TIME        (0),
        .BYTE_WRITE_WIDTH_A     (32),
        .BYTE_WRITE_WIDTH_B     (32),
        .CASCADE_HEIGHT         (0),
        .CLOCKING_MODE          ("common_clock"),
        .ECC_MODE               ("no_ecc"),
        .MEMORY_INIT_FILE       ("none"),
        .MEMORY_INIT_PARAM      ("0"),
        .MEMORY_OPTIMIZATION    ("true"),
        .MEMORY_PRIMITIVE       ("block"),
        .MEMORY_SIZE            (131072),
        .MESSAGE_CONTROL        (0),
        .READ_DATA_WIDTH_A      (32),
        .READ_DATA_WIDTH_B      (32),
        .READ_LATENCY_A         (1),
        .READ_LATENCY_B         (1),
        .READ_RESET_VALUE_A     ("0"),
        .READ_RESET_VALUE_B     ("0"),
        .RST_MODE_A             ("SYNC"),
        .RST_MODE_B             ("SYNC"),
        .SIM_ASSERT_CHK         (0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT           (0),
        .WAKEUP_TIME            ("disable_sleep"),
        .WRITE_DATA_WIDTH_A     (32),
        .WRITE_DATA_WIDTH_B     (32),
        .WRITE_MODE_A           ("no_change"),
        .WRITE_MODE_B           ("no_change")
    ) profile_memory (
        .clka            (clk),
        .clkb            (clk),

        .ena             (
            write_enable
            || read_enable_a
        ),

        .enb             (read_enable_b),

        .wea             (write_enable),
        .web             (1'b0),

        .addra           (port_a_address),
        .addrb           (read_address_b),

        .dina            (write_data),
        .dinb            (32'd0),

        .douta           (read_data_a),
        .doutb           (read_data_b),

        .rsta            (1'b0),
        .rstb            (1'b0),

        .regcea          (1'b1),
        .regceb          (1'b1),

        .sleep           (1'b0),

        .injectdbiterra  (1'b0),
        .injectdbiterrb  (1'b0),
        .injectsbiterra  (1'b0),
        .injectsbiterrb  (1'b0)
    );

`endif

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            write_enable
            && (
                read_enable_a
                || read_enable_b
            )
        )
        begin
            $display(
                "ERROR: profile write attempted during dual read"
            );

            $fatal(1);
        end
    end

`endif

endmodule
