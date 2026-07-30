`timescale 1ns/1ps

module tb_ntt256_coeff_bram;

    import ntt256_profile_pkg::*;

    logic clk = 1'b0;
    logic reset_n = 1'b0;

    logic port_a_enable = 1'b0;
    logic port_a_write_enable = 1'b0;
    logic [7:0] port_a_address = 8'd0;
    logic [31:0] port_a_write_data = 32'd0;
    logic [31:0] port_a_read_data;

    logic port_b_enable = 1'b0;
    logic port_b_write_enable = 1'b0;
    logic [7:0] port_b_address = 8'd0;
    logic [31:0] port_b_write_data = 32'd0;
    logic [31:0] port_b_read_data;

    logic schedule_start = 1'b0;
    logic schedule_advance = 1'b0;

    logic schedule_busy;
    logic schedule_valid;
    logic schedule_done;

    logic [9:0] operation_index;
    logic [2:0] stage;
    logic [6:0] butterfly_index;

    logic [7:0] schedule_address_a;
    logic [7:0] schedule_address_b;
    logic [7:0] schedule_twiddle_address;

    logic [7:0] twiddle_address = 8'd0;
    logic [31:0] twiddle_data;

    logic done_seen = 1'b0;

    logic [31:0] initial_memory [0:255];

    logic [31:0] expected_stage0 [0:255];
    logic [31:0] expected_stage1 [0:255];
    logic [31:0] expected_stage2 [0:255];
    logic [31:0] expected_stage3 [0:255];
    logic [31:0] expected_stage4 [0:255];
    logic [31:0] expected_stage5 [0:255];
    logic [31:0] expected_stage6 [0:255];
    logic [31:0] expected_stage7 [0:255];

    logic [31:0] expected_final [0:255];

    logic [31:0] value_a;
    logic [31:0] value_b;
    logic [31:0] current_twiddle;

    logic [31:0] product_mod;
    logic [31:0] result_a;
    logic [31:0] result_b;

    logic [63:0] wide_product;
    logic [63:0] wide_sum;
    logic [63:0] wide_difference;

    logic [2:0] current_stage;
    logic [6:0] current_butterfly;

    logic [7:0] current_address_a;
    logic [7:0] current_address_b;
    logic [7:0] current_twiddle_address;

    integer address;
    integer operation;

    ntt256_coeff_bram coefficient_memory (
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

    ntt256_schedule_core schedule (
        .clk              (clk),
        .reset_n          (reset_n),

        .start            (schedule_start),
        .advance          (schedule_advance),

        .busy             (schedule_busy),
        .valid            (schedule_valid),
        .done             (schedule_done),

        .operation_index  (operation_index),
        .stage            (stage),
        .butterfly_index  (butterfly_index),

        .address_a        (schedule_address_a),
        .address_b        (schedule_address_b),
        .twiddle_address  (schedule_twiddle_address)
    );

    ntt256_twiddle_rom #(
        .INIT_FILE(
            "../model/golden_n256/forward_twiddles.mem"
        )
    ) forward_twiddle_rom (
        .clk     (clk),
        .address (twiddle_address),
        .data    (twiddle_data)
    );

    always #5 clk = ~clk;

    always @(posedge clk)
    begin
        if (!reset_n)
            done_seen <= 1'b0;
        else if (schedule_done)
            done_seen <= 1'b1;
    end

    function automatic logic [31:0] expected_stage_value(
        input integer stage_number,
        input integer memory_address
    );
        begin
            case (stage_number)
                0:
                    expected_stage_value =
                        expected_stage0[memory_address];

                1:
                    expected_stage_value =
                        expected_stage1[memory_address];

                2:
                    expected_stage_value =
                        expected_stage2[memory_address];

                3:
                    expected_stage_value =
                        expected_stage3[memory_address];

                4:
                    expected_stage_value =
                        expected_stage4[memory_address];

                5:
                    expected_stage_value =
                        expected_stage5[memory_address];

                6:
                    expected_stage_value =
                        expected_stage6[memory_address];

                7:
                    expected_stage_value =
                        expected_stage7[memory_address];

                default:
                    expected_stage_value =
                        32'hxxxxxxxx;
            endcase
        end
    endfunction

    task automatic read_memory_word(
        input integer memory_address,
        output logic [31:0] value
    );
        begin
            @(negedge clk);

            port_a_enable       = 1'b1;
            port_a_write_enable = 1'b0;
            port_a_address      = memory_address[7:0];

            port_b_enable       = 1'b0;
            port_b_write_enable = 1'b0;

            /*
             * Read data becomes available after the next rising edge.
             */
            @(negedge clk);

            value = port_a_read_data;
        end
    endtask

    task automatic compare_stage_memory(
        input integer stage_number
    );
        integer memory_address;
        logic [31:0] actual;
        logic [31:0] expected;

        begin
            for (
                memory_address = 0;
                memory_address < NTT_N;
                memory_address = memory_address + 1
            )
            begin
                read_memory_word(
                    memory_address,
                    actual
                );

                expected = expected_stage_value(
                    stage_number,
                    memory_address
                );

                if (actual !== expected)
                begin
                    $display(
                        "FAIL STAGE stage=%0d address=%0d result=%0d expected=%0d",
                        stage_number,
                        memory_address,
                        actual,
                        expected
                    );

                    $fatal(1);
                end
            end

            @(negedge clk);

            port_a_enable = 1'b0;
            port_b_enable = 1'b0;

            $display(
                "PASS: stage %0d coefficient BRAM matches golden model",
                stage_number
            );
        end
    endtask

    task automatic compare_final_memory;
        integer memory_address;
        logic [31:0] actual;

        begin
            for (
                memory_address = 0;
                memory_address < NTT_N;
                memory_address = memory_address + 1
            )
            begin
                read_memory_word(
                    memory_address,
                    actual
                );

                if (
                    actual
                    !== expected_final[memory_address]
                )
                begin
                    $display(
                        "FAIL FINAL address=%0d result=%0d expected=%0d",
                        memory_address,
                        actual,
                        expected_final[memory_address]
                    );

                    $fatal(1);
                end
            end

            @(negedge clk);

            port_a_enable = 1'b0;
            port_b_enable = 1'b0;
        end
    endtask

    initial
    begin
        $readmemh(
            "../model/golden_n256/forward_a_bit_reversed_input.mem",
            initial_memory
        );

        $readmemh(
            "../model/golden_n256/forward_a_stage0.mem",
            expected_stage0
        );

        $readmemh(
            "../model/golden_n256/forward_a_stage1.mem",
            expected_stage1
        );

        $readmemh(
            "../model/golden_n256/forward_a_stage2.mem",
            expected_stage2
        );

        $readmemh(
            "../model/golden_n256/forward_a_stage3.mem",
            expected_stage3
        );

        $readmemh(
            "../model/golden_n256/forward_a_stage4.mem",
            expected_stage4
        );

        $readmemh(
            "../model/golden_n256/forward_a_stage5.mem",
            expected_stage5
        );

        $readmemh(
            "../model/golden_n256/forward_a_stage6.mem",
            expected_stage6
        );

        $readmemh(
            "../model/golden_n256/forward_a_stage7.mem",
            expected_stage7
        );

        $readmemh(
            "../model/golden_n256/forward_a.mem",
            expected_final
        );

        repeat (4) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        /*
         * Load the golden bit-reversed input through port A.
         */
        for (
            address = 0;
            address < NTT_N;
            address = address + 1
        )
        begin
            @(negedge clk);

            port_a_enable       = 1'b1;
            port_a_write_enable = 1'b1;
            port_a_address      = address[7:0];
            port_a_write_data   = initial_memory[address];

            port_b_enable       = 1'b0;
            port_b_write_enable = 1'b0;
        end

        @(negedge clk);

        port_a_enable       = 1'b0;
        port_a_write_enable = 1'b0;

        $display(
            "PASS: loaded 256 bit-reversed coefficients into dual-port BRAM"
        );

        /*
         * Launch the eight-stage butterfly schedule.
         */
        @(negedge clk);
        schedule_start = 1'b1;

        @(negedge clk);
        schedule_start = 1'b0;

        if (
            schedule_busy !== 1'b1 ||
            schedule_valid !== 1'b1
        )
        begin
            $display(
                "FAIL: butterfly schedule did not start"
            );

            $fatal(1);
        end

        for (
            operation = 0;
            operation < NTT_BUTTERFLIES;
            operation = operation + 1
        )
        begin
            if (schedule_valid !== 1'b1)
            begin
                $display(
                    "FAIL: schedule invalid at operation %0d",
                    operation
                );

                $fatal(1);
            end

            if (
                operation_index
                !== operation[9:0]
            )
            begin
                $display(
                    "FAIL OPERATION result=%0d expected=%0d",
                    operation_index,
                    operation
                );

                $fatal(1);
            end

            current_stage =
                stage;

            current_butterfly =
                butterfly_index;

            current_address_a =
                schedule_address_a;

            current_address_b =
                schedule_address_b;

            current_twiddle_address =
                schedule_twiddle_address;

            if (
                current_address_a
                == current_address_b
            )
            begin
                $display(
                    "FAIL: identical butterfly addresses operation=%0d address=%0d",
                    operation,
                    current_address_a
                );

                $fatal(1);
            end

            /*
             * Issue two simultaneous coefficient reads and one
             * synchronous twiddle-ROM read.
             */
            @(negedge clk);

            port_a_enable       = 1'b1;
            port_a_write_enable = 1'b0;
            port_a_address      = current_address_a;

            port_b_enable       = 1'b1;
            port_b_write_enable = 1'b0;
            port_b_address      = current_address_b;

            twiddle_address =
                current_twiddle_address;

            /*
             * One rising edge later all three values are available.
             */
            @(negedge clk);

            value_a =
                port_a_read_data;

            value_b =
                port_b_read_data;

            current_twiddle =
                twiddle_data;

            /*
             * Behavioral modular arithmetic here isolates and tests
             * the memory transaction architecture. The next core will
             * replace this calculation with butterfly_core.
             */
            wide_product =
                {32'd0, value_b}
                * current_twiddle;

            product_mod =
                wide_product % NTT_Q;

            wide_sum =
                {32'd0, value_a}
                + {32'd0, product_mod};

            result_a =
                wide_sum % NTT_Q;

            wide_difference =
                {32'd0, value_a}
                + {32'd0, NTT_Q}
                - {32'd0, product_mod};

            result_b =
                wide_difference % NTT_Q;

            /*
             * Write both butterfly outputs simultaneously. Advance
             * the schedule on the same edge that commits writeback.
             */
            port_a_enable       = 1'b1;
            port_a_write_enable = 1'b1;
            port_a_address      = current_address_a;
            port_a_write_data   = result_a;

            port_b_enable       = 1'b1;
            port_b_write_enable = 1'b1;
            port_b_address      = current_address_b;
            port_b_write_data   = result_b;

            schedule_advance = 1'b1;

            @(negedge clk);

            port_a_enable       = 1'b0;
            port_a_write_enable = 1'b0;

            port_b_enable       = 1'b0;
            port_b_write_enable = 1'b0;

            schedule_advance = 1'b0;

            /*
             * Freeze the new schedule entry and inspect the complete
             * BRAM after every stage.
             */
            if (current_butterfly == 7'd127)
            begin
                compare_stage_memory(
                    current_stage
                );
            end
        end

        if (done_seen !== 1'b1)
        begin
            $display(
                "FAIL: final schedule completion was not observed"
            );

            $fatal(1);
        end

        if (
            schedule_busy !== 1'b0 ||
            schedule_valid !== 1'b0
        )
        begin
            $display(
                "FAIL: schedule remained active after 1024 operations"
            );

            $fatal(1);
        end

        compare_final_memory();

        $display(
            "PASS: final N=256 cyclic NTT memory matches golden model"
        );

        $display(
            "PASS: 1024 dual-port BRAM butterfly read/write transactions"
        );

        $display(
            "Coefficient BRAM: %0d words x 32 bits",
            NTT_N
        );

        $display(
            "Ports: 2, synchronous read latency: 1 clock"
        );

        $finish;
    end

endmodule
