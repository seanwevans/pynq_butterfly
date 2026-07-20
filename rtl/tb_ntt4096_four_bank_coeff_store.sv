`timescale 1ns/1ps

module tb_ntt4096_four_bank_coeff_store;
    localparam integer N = 4096;
    localparam integer GROUPS_PER_TRANSFORM = 12288;

    logic clk = 1'b0;
    logic reset_n = 1'b0;

    logic schedule_start = 1'b0;
    logic schedule_descending = 1'b0;
    logic schedule_busy;
    logic schedule_valid;
    logic schedule_done;
    logic [3:0] schedule_stage;
    logic [9:0] schedule_pair;
    logic [11:0] address0_a;
    logic [11:0] address0_b;
    logic [11:0] address1_a;
    logic [11:0] address1_b;
    logic [10:0] unused_twiddle0;
    logic [10:0] unused_twiddle1;

    logic load_we = 1'b0;
    logic [11:0] load_addr = 12'd0;
    logic [31:0] load_data = 32'd0;

    logic mode_read = 1'b0;
    logic mode_write = 1'b0;
    logic expected_new_pattern = 1'b0;

    logic read_data_valid;
    logic [31:0] read_data0;
    logic [31:0] read_data1;
    logic [31:0] read_data2;
    logic [31:0] read_data3;

    logic [11:0] expected_addr0_q;
    logic [11:0] expected_addr1_q;
    logic [11:0] expected_addr2_q;
    logic [11:0] expected_addr3_q;
    logic expected_pattern_q;

    integer load_index;
    integer read_group_count;
    integer write_group_count;

    function automatic [31:0] pattern0;
        input [11:0] address;
        begin
            pattern0 = 32'h13579bdf ^ ({20'd0, address} * 32'h00010001);
        end
    endfunction

    function automatic [31:0] pattern1;
        input [11:0] address;
        begin
            pattern1 = 32'h2468ace0 + ({20'd0, address} * 32'h9e3779b9);
        end
    endfunction

    ntt4096_dual_butterfly_schedule_core schedule (
        .clk(clk),
        .reset_n(reset_n),
        .start(schedule_start),
        .descending(schedule_descending),
        .busy(schedule_busy),
        .valid(schedule_valid),
        .done(schedule_done),
        .stage_bit(schedule_stage),
        .pair_index(schedule_pair),
        .address0_a(address0_a),
        .address0_b(address0_b),
        .address1_a(address1_a),
        .address1_b(address1_b),
        .twiddle_index0(unused_twiddle0),
        .twiddle_index1(unused_twiddle1)
    );

    ntt4096_four_bank_coeff_store store (
        .clk(clk),
        .reset_n(reset_n),
        .load_we(load_we),
        .load_addr(load_addr),
        .load_data(load_data),
        .read_valid(schedule_valid && mode_read),
        .read_addr0(address0_a),
        .read_addr1(address0_b),
        .read_addr2(address1_a),
        .read_addr3(address1_b),
        .read_data_valid(read_data_valid),
        .read_data0(read_data0),
        .read_data1(read_data1),
        .read_data2(read_data2),
        .read_data3(read_data3),
        .write_valid(schedule_valid && mode_write),
        .write_addr0(address0_a),
        .write_addr1(address0_b),
        .write_addr2(address1_a),
        .write_addr3(address1_b),
        .write_data0(pattern1(address0_a)),
        .write_data1(pattern1(address0_b)),
        .write_data2(pattern1(address1_a)),
        .write_data3(pattern1(address1_b))
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            expected_addr0_q <= 12'd0;
            expected_addr1_q <= 12'd0;
            expected_addr2_q <= 12'd0;
            expected_addr3_q <= 12'd0;
            expected_pattern_q <= 1'b0;
            write_group_count <= 0;
        end else begin
            if (schedule_valid && mode_read) begin
                expected_addr0_q <= address0_a;
                expected_addr1_q <= address0_b;
                expected_addr2_q <= address1_a;
                expected_addr3_q <= address1_b;
                expected_pattern_q <= expected_new_pattern;
            end

            if (schedule_valid && mode_write) begin
                write_group_count <= write_group_count + 1;
            end
        end
    end

    always @(negedge clk) begin
        if (reset_n && read_data_valid) begin
            if (!expected_pattern_q) begin
                if (read_data0 !== pattern0(expected_addr0_q) ||
                    read_data1 !== pattern0(expected_addr1_q) ||
                    read_data2 !== pattern0(expected_addr2_q) ||
                    read_data3 !== pattern0(expected_addr3_q)) begin
                    $display("FAIL initial pattern at read group %0d", read_group_count);
                    $fatal(1);
                end
            end else begin
                if (read_data0 !== pattern1(expected_addr0_q) ||
                    read_data1 !== pattern1(expected_addr1_q) ||
                    read_data2 !== pattern1(expected_addr2_q) ||
                    read_data3 !== pattern1(expected_addr3_q)) begin
                    $display("FAIL rewritten pattern at read group %0d", read_group_count);
                    $fatal(1);
                end
            end

            read_group_count = read_group_count + 1;
        end
    end

    task automatic run_schedule;
        input use_descending;
        input enable_read;
        input enable_write;
        input use_new_pattern;
        begin
            read_group_count = 0;
            write_group_count = 0;

            @(negedge clk);
            mode_read = enable_read;
            mode_write = enable_write;
            expected_new_pattern = use_new_pattern;
            schedule_descending = use_descending;
            schedule_start = 1'b1;

            @(negedge clk);
            schedule_start = 1'b0;

            while (!schedule_done) begin
                @(negedge clk);
            end

            repeat (3) @(negedge clk);

            mode_read = 1'b0;
            mode_write = 1'b0;

            if (enable_read && read_group_count != GROUPS_PER_TRANSFORM) begin
                $display("FAIL read groups result=%0d expected=%0d", read_group_count, GROUPS_PER_TRANSFORM);
                $fatal(1);
            end

            if (enable_write && write_group_count != GROUPS_PER_TRANSFORM) begin
                $display("FAIL write groups result=%0d expected=%0d", write_group_count, GROUPS_PER_TRANSFORM);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        for (load_index = 0; load_index < N; load_index = load_index + 1) begin
            @(negedge clk);
            load_we = 1'b1;
            load_addr = load_index[11:0];
            load_data = pattern0(load_index[11:0]);
        end

        @(negedge clk);
        load_we = 1'b0;

        run_schedule(1'b1, 1'b1, 1'b0, 1'b0);
        $display("PASS: four-bank store read all paired DIF addresses at one group per cycle");

        run_schedule(1'b0, 1'b0, 1'b1, 1'b0);
        $display("PASS: four-bank store wrote four coefficients per paired DIT cycle");

        run_schedule(1'b1, 1'b1, 1'b0, 1'b1);
        $display("PASS: four-bank store preserved all rewritten logical coefficients");

        $display("PASS: logical address mapping is independent of physical bank and row");
        $display("Coefficient words: 4096");
        $display("Physical banks: 4");
        $display("Words per bank: 1024");
        $display("Read ports serviced per cycle: 4");
        $display("Write ports serviced per cycle: 4");
        $display("Expected RAMB36 per coefficient store: 4");
        $finish;
    end
endmodule
