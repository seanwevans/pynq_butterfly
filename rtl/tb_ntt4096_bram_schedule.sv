`timescale 1ns/1ps

module tb_ntt4096_bram_schedule;

    localparam integer N =
        4096;

    localparam integer STAGES =
        12;

    localparam integer BUTTERFLIES_PER_STAGE =
        2048;

    localparam integer TOTAL_BUTTERFLIES =
        24576;

    localparam logic [31:0] Q =
        32'd1073692673;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic start =
        1'b0;

    logic advance =
        1'b0;

    logic schedule_busy;
    logic schedule_valid;
    logic schedule_done;

    logic [14:0] operation;
    logic [3:0]  schedule_stage;
    logic [11:0] schedule_group;
    logic [11:0] schedule_j;

    logic [11:0] left_addr;
    logic [11:0] right_addr;
    logic [11:0] twiddle_addr;

    logic rom_enable =
        1'b0;

    logic [31:0] twiddle_read_data;

    logic port_a_enable =
        1'b0;

    logic port_a_write_enable =
        1'b0;

    logic [11:0] port_a_address =
        12'd0;

    logic [31:0] port_a_write_data =
        32'd0;

    logic [31:0] port_a_read_data;

    logic port_b_enable =
        1'b0;

    logic port_b_write_enable =
        1'b0;

    logic [11:0] port_b_address =
        12'd0;

    logic [31:0] port_b_write_data =
        32'd0;

    logic [31:0] port_b_read_data;

    logic [31:0] input_bit_reversed [0:N-1];
    logic [31:0] expected_stage [0:N-1];

    logic [31:0] left_value;
    logic [31:0] right_value;
    logic [31:0] twiddle_value;

    logic [63:0] wide_product;
    logic [31:0] product_value;

    logic [32:0] sum_ext;
    logic [32:0] difference_ext;

    logic [31:0] left_result;
    logic [31:0] right_result;

    integer address;
    integer stage_index;
    integer butterfly_in_stage;
    integer completed_butterflies;

    ntt4096_schedule_core scheduler (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (start),
        .advance      (advance),

        .busy         (schedule_busy),
        .valid        (schedule_valid),
        .done         (schedule_done),

        .operation    (operation),
        .stage        (schedule_stage),
        .group        (schedule_group),
        .j            (schedule_j),

        .left_addr    (left_addr),
        .right_addr   (right_addr),
        .twiddle_addr (twiddle_addr)
    );

    ntt4096_twiddle_rom #(
        .INIT_FILE(
            "../tests/fixtures/ntt_n4096/forward_twiddles.mem"
        )
    ) forward_twiddle_rom (
        .clk       (clk),
        .enable    (rom_enable),
        .address   (twiddle_addr),
        .read_data (twiddle_read_data)
    );

    ntt4096_coeff_bram coefficient_memory (
        .clk                 (clk),

        .port_a_enable       (port_a_enable),
        .port_a_write_enable (port_a_write_enable),
        .port_a_address      (port_a_address),
        .port_a_write_data   (port_a_write_data),
        .port_a_read_data    (port_a_read_data),

        .port_b_enable       (port_b_enable),
        .port_b_write_enable (port_b_write_enable),
        .port_b_address      (port_b_address),
        .port_b_write_data   (port_b_write_data),
        .port_b_read_data    (port_b_read_data)
    );

    always #5 clk = ~clk;

    task automatic load_expected_stage(
        input integer requested_stage
    );
        begin
            case (requested_stage)
                0:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage0.mem",
                        expected_stage
                    );
                end

                1:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage1.mem",
                        expected_stage
                    );
                end

                2:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage2.mem",
                        expected_stage
                    );
                end

                3:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage3.mem",
                        expected_stage
                    );
                end

                4:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage4.mem",
                        expected_stage
                    );
                end

                5:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage5.mem",
                        expected_stage
                    );
                end

                6:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage6.mem",
                        expected_stage
                    );
                end

                7:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage7.mem",
                        expected_stage
                    );
                end

                8:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage8.mem",
                        expected_stage
                    );
                end

                9:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage9.mem",
                        expected_stage
                    );
                end

                10:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage10.mem",
                        expected_stage
                    );
                end

                11:
                begin
                    $readmemh(
                        "../tests/fixtures/ntt_n4096/forward_a_stage11.mem",
                        expected_stage
                    );
                end

                default:
                begin
                    $display(
                        "FAIL: invalid expected stage %0d",
                        requested_stage
                    );

                    $fatal(1);
                end
            endcase
        end
    endtask

    task automatic compare_loaded_input;
        begin
            port_b_enable =
                1'b0;

            port_b_write_enable =
                1'b0;

            port_a_write_enable =
                1'b0;

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                port_a_enable =
                    1'b1;

                port_a_address =
                    address[11:0];

                @(posedge clk);
                @(negedge clk);

                if (
                    port_a_read_data
                    !== input_bit_reversed[address]
                )
                begin
                    $display(
                        "FAIL LOADED INPUT address=%0d result=%0d expected=%0d",
                        address,
                        port_a_read_data,
                        input_bit_reversed[address]
                    );

                    $fatal(1);
                end
            end

            @(negedge clk);

            port_a_enable =
                1'b0;

            $display(
                "PASS: loaded 4096 bit-reversed coefficients into dual-port BRAM"
            );
        end
    endtask

    task automatic compare_stage_memory(
        input integer requested_stage
    );
        begin
            load_expected_stage(
                requested_stage
            );

            port_b_enable =
                1'b0;

            port_b_write_enable =
                1'b0;

            port_a_write_enable =
                1'b0;

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                port_a_enable =
                    1'b1;

                port_a_address =
                    address[11:0];

                @(posedge clk);
                @(negedge clk);

                if (
                    port_a_read_data
                    !== expected_stage[address]
                )
                begin
                    $display(
                        "FAIL STAGE MEMORY stage=%0d address=%0d result=%0d expected=%0d",
                        requested_stage,
                        address,
                        port_a_read_data,
                        expected_stage[address]
                    );

                    $fatal(1);
                end
            end

            @(negedge clk);

            port_a_enable =
                1'b0;

            $display(
                "PASS: stage %0d coefficient BRAM matches golden model",
                requested_stage
            );
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_a_bit_reversed.mem",
            input_bit_reversed
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        /*
         * Load the bit-reversed input through one synchronous BRAM
         * write port.
         */
        for (
            address = 0;
            address < N;
            address = address + 1
        )
        begin
            @(negedge clk);

            port_a_enable =
                1'b1;

            port_a_write_enable =
                1'b1;

            port_a_address =
                address[11:0];

            port_a_write_data =
                input_bit_reversed[address];

            @(posedge clk);
        end

        @(negedge clk);

        port_a_enable =
            1'b0;

        port_a_write_enable =
            1'b0;

        compare_loaded_input();

        @(negedge clk);

        start =
            1'b1;

        @(posedge clk);
        @(negedge clk);

        start =
            1'b0;

        completed_butterflies =
            0;

        for (
            stage_index = 0;
            stage_index < STAGES;
            stage_index = stage_index + 1
        )
        begin
            for (
                butterfly_in_stage = 0;
                butterfly_in_stage < BUTTERFLIES_PER_STAGE;
                butterfly_in_stage = butterfly_in_stage + 1
            )
            begin
                if (
                    !schedule_busy
                    || !schedule_valid
                    || schedule_done
                    || schedule_stage !== stage_index[3:0]
                    || operation !== completed_butterflies[14:0]
                )
                begin
                    $display(
                        "FAIL SCHEDULER BEFORE READ operation=%0d stage=%0d busy=%0b valid=%0b done=%0b actual_operation=%0d actual_stage=%0d",
                        completed_butterflies,
                        stage_index,
                        schedule_busy,
                        schedule_valid,
                        schedule_done,
                        operation,
                        schedule_stage
                    );

                    $fatal(1);
                end

                /*
                 * Issue both coefficient reads and the twiddle-ROM
                 * read on the same clock.
                 */
                @(negedge clk);

                port_a_enable =
                    1'b1;

                port_a_write_enable =
                    1'b0;

                port_a_address =
                    left_addr;

                port_b_enable =
                    1'b1;

                port_b_write_enable =
                    1'b0;

                port_b_address =
                    right_addr;

                rom_enable =
                    1'b1;

                @(posedge clk);
                @(negedge clk);

                left_value =
                    port_a_read_data;

                right_value =
                    port_b_read_data;

                twiddle_value =
                    twiddle_read_data;

                /*
                 * Behavioral modular multiplication is intentional at
                 * this checkpoint. The test isolates address scheduling
                 * and dual-port BRAM read/write semantics.
                 */
                wide_product =
                    {32'd0, right_value}
                    * {32'd0, twiddle_value};

                product_value =
                    wide_product % Q;

                sum_ext =
                    {1'b0, left_value}
                    + {1'b0, product_value};

                if (sum_ext >= {1'b0, Q})
                begin
                    left_result =
                        sum_ext - {1'b0, Q};
                end
                else
                begin
                    left_result =
                        sum_ext[31:0];
                end

                difference_ext =
                    {1'b0, left_value}
                    + {1'b0, Q}
                    - {1'b0, product_value};

                if (difference_ext >= {1'b0, Q})
                begin
                    right_result =
                        difference_ext - {1'b0, Q};
                end
                else
                begin
                    right_result =
                        difference_ext[31:0];
                end

                /*
                 * Write both butterfly outputs and advance the
                 * scheduler on the same edge. The current schedule
                 * entry remains stable until this edge.
                 */
                port_a_enable =
                    1'b1;

                port_a_write_enable =
                    1'b1;

                port_a_address =
                    left_addr;

                port_a_write_data =
                    left_result;

                port_b_enable =
                    1'b1;

                port_b_write_enable =
                    1'b1;

                port_b_address =
                    right_addr;

                port_b_write_data =
                    right_result;

                advance =
                    1'b1;

                @(posedge clk);
                @(negedge clk);

                port_a_write_enable =
                    1'b0;

                port_b_write_enable =
                    1'b0;

                advance =
                    1'b0;

                completed_butterflies =
                    completed_butterflies + 1;
            end

            if (stage_index == STAGES - 1)
            begin
                if (
                    schedule_busy
                    || schedule_valid
                    || !schedule_done
                )
                begin
                    $display(
                        "FAIL FINAL SCHEDULE STATE busy=%0b valid=%0b done=%0b",
                        schedule_busy,
                        schedule_valid,
                        schedule_done
                    );

                    $fatal(1);
                end
            end
            else
            begin
                if (
                    !schedule_busy
                    || !schedule_valid
                    || schedule_done
                    || schedule_stage !== (stage_index + 1)
                )
                begin
                    $display(
                        "FAIL STAGE TRANSITION completed_stage=%0d next_stage=%0d busy=%0b valid=%0b done=%0b",
                        stage_index,
                        schedule_stage,
                        schedule_busy,
                        schedule_valid,
                        schedule_done
                    );

                    $fatal(1);
                end
            end

            rom_enable =
                1'b0;

            port_b_enable =
                1'b0;

            compare_stage_memory(
                stage_index
            );
        end

        if (
            completed_butterflies
            != TOTAL_BUTTERFLIES
        )
        begin
            $display(
                "FAIL BUTTERFLY COUNT result=%0d expected=%0d",
                completed_butterflies,
                TOTAL_BUTTERFLIES
            );

            $fatal(1);
        end

        $display(
            "PASS: all 12 N=4096 stages agree with golden model"
        );

        $display(
            "PASS: 24576 dual-port BRAM butterfly read/write transactions"
        );

        $display(
            "Coefficient BRAM: 4096 words x 32 bits"
        );

        $display(
            "Ports: 2, synchronous read latency: 1 clock"
        );

        $finish;
    end

endmodule
