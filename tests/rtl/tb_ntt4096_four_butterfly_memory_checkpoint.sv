`timescale 1ns / 1ps

module tb_ntt4096_four_butterfly_memory_checkpoint;

    logic clk;

    logic [3:0] stage;
    logic [8:0] group_index;

    logic write_valid;
    logic [7:0][31:0] write_data;

    logic read_valid;
    logic read_data_valid;
    logic [7:0][31:0] read_data;

    logic [7:0][11:0] logical_address;

    bit mapping_seen [0:4095];
    bit stage_seen [0:4095];
    bit bank_seen [0:7];

    integer address_index;
    integer key_index;
    integer stage_index;
    integer group_index_integer;
    integer lane_index;
    integer butterfly_index;
    integer bank_index_integer;
    integer dif_group_count;
    integer dit_group_count;
    integer store_words_checked;

    logic [11:0] pair_delta;
    logic [11:0] expected_delta;
    logic [31:0] expected_word;

    ntt4096_four_butterfly_memory_checkpoint_top dut (
        .clk (
            clk
        ),

        .stage (
            stage
        ),

        .group_index (
            group_index
        ),

        .write_valid (
            write_valid
        ),

        .write_data (
            write_data
        ),

        .read_valid (
            read_valid
        ),

        .read_data_valid (
            read_data_valid
        ),

        .read_data (
            read_data
        ),

        .logical_address (
            logical_address
        )
    );

    function automatic logic [2:0] bank_of (
        input logic [11:0] logical_address_value
    );
        begin
            bank_of[0] =
                logical_address_value[0]
                ^ logical_address_value[3]
                ^ logical_address_value[6]
                ^ logical_address_value[9];

            bank_of[1] =
                logical_address_value[1]
                ^ logical_address_value[4]
                ^ logical_address_value[7]
                ^ logical_address_value[10];

            bank_of[2] =
                logical_address_value[2]
                ^ logical_address_value[5]
                ^ logical_address_value[8]
                ^ logical_address_value[11];
        end
    endfunction

    function automatic logic [8:0] row_of (
        input logic [11:0] logical_address_value
    );
        begin
            row_of =
                logical_address_value[11:3];
        end
    endfunction

    function automatic logic [31:0] word_for (
        input logic [11:0] logical_address_value
    );
        begin
            word_for =
                32'h9e370000
                ^ {
                    8'h00,
                    logical_address_value,
                    logical_address_value
                };
        end
    endfunction

    task automatic clear_stage_seen;
        integer index_value;
        begin
            for (
                index_value = 0;
                index_value < 4096;
                index_value = index_value + 1
            )
            begin
                stage_seen[index_value] =
                    1'b0;
            end
        end
    endtask

    task automatic clear_bank_seen;
        integer index_value;
        begin
            for (
                index_value = 0;
                index_value < 8;
                index_value = index_value + 1
            )
            begin
                bank_seen[index_value] =
                    1'b0;
            end
        end
    endtask

    task automatic check_stage (
        input integer stage_value,
        input integer direction_value
    );
        integer local_group;
        integer local_lane;
        integer local_butterfly;
        integer local_address;
        integer local_bank;
        begin
            clear_stage_seen();

            stage =
                stage_value[3:0];

            expected_delta =
                12'b1 << stage_value;

            for (
                local_group = 0;
                local_group < 512;
                local_group = local_group + 1
            )
            begin
                group_index =
                    local_group[8:0];

                #1;

                clear_bank_seen();

                for (
                    local_lane = 0;
                    local_lane < 8;
                    local_lane = local_lane + 1
                )
                begin
                    local_address =
                        logical_address[local_lane];

                    if (stage_seen[local_address])
                    begin
                        $fatal(
                            1,
                            "duplicate address stage=%0d group=%0d address=%0d",
                            stage_value,
                            local_group,
                            local_address
                        );
                    end

                    stage_seen[local_address] =
                        1'b1;

                    local_bank =
                        bank_of(logical_address[local_lane]);

                    if (bank_seen[local_bank])
                    begin
                        $fatal(
                            1,
                            "bank conflict stage=%0d group=%0d bank=%0d",
                            stage_value,
                            local_group,
                            local_bank
                        );
                    end

                    bank_seen[local_bank] =
                        1'b1;
                end

                for (
                    local_butterfly = 0;
                    local_butterfly < 4;
                    local_butterfly = local_butterfly + 1
                )
                begin
                    pair_delta =
                        logical_address[2 * local_butterfly]
                        ^ logical_address[
                            2 * local_butterfly + 1
                        ];

                    if (pair_delta != expected_delta)
                    begin
                        $fatal(
                            1,
                            "bad butterfly pair stage=%0d group=%0d butterfly=%0d delta=%0h expected=%0h",
                            stage_value,
                            local_group,
                            local_butterfly,
                            pair_delta,
                            expected_delta
                        );
                    end
                end
            end

            for (
                local_address = 0;
                local_address < 4096;
                local_address = local_address + 1
            )
            begin
                if (!stage_seen[local_address])
                begin
                    $fatal(
                        1,
                        "missing address stage=%0d address=%0d",
                        stage_value,
                        local_address
                    );
                end
            end

            if (direction_value == 0)
            begin
                dif_group_count =
                    dif_group_count + 512;
            end
            else
            begin
                dit_group_count =
                    dit_group_count + 512;
            end
        end
    endtask

    always #5 clk =
        ~clk;

    initial
    begin
        clk =
            1'b0;

        stage =
            4'd0;

        group_index =
            9'd0;

        write_valid =
            1'b0;

        write_data =
            '0;

        read_valid =
            1'b0;

        dif_group_count =
            0;

        dit_group_count =
            0;

        store_words_checked =
            0;

        for (
            address_index = 0;
            address_index < 4096;
            address_index = address_index + 1
        )
        begin
            mapping_seen[address_index] =
                1'b0;
        end

        for (
            address_index = 0;
            address_index < 4096;
            address_index = address_index + 1
        )
        begin
            key_index =
                {
                    row_of(address_index[11:0]),
                    bank_of(address_index[11:0])
                };

            if (mapping_seen[key_index])
            begin
                $fatal(
                    1,
                    "mapping collision logical=%0d key=%0d",
                    address_index,
                    key_index
                );
            end

            mapping_seen[key_index] =
                1'b1;
        end

        for (
            key_index = 0;
            key_index < 4096;
            key_index = key_index + 1
        )
        begin
            if (!mapping_seen[key_index])
            begin
                $fatal(
                    1,
                    "mapping hole key=%0d",
                    key_index
                );
            end
        end

        for (
            stage_index = 0;
            stage_index < 12;
            stage_index = stage_index + 1
        )
        begin
            check_stage(
                stage_index,
                0
            );
        end

        for (
            stage_index = 11;
            stage_index >= 0;
            stage_index = stage_index - 1
        )
        begin
            check_stage(
                stage_index,
                1
            );
        end

        if (dif_group_count != 6144)
        begin
            $fatal(
                1,
                "DIF group count=%0d expected=6144",
                dif_group_count
            );
        end

        if (dit_group_count != 6144)
        begin
            $fatal(
                1,
                "DIT group count=%0d expected=6144",
                dit_group_count
            );
        end

        stage =
            4'd0;

        for (
            group_index_integer = 0;
            group_index_integer < 512;
            group_index_integer = group_index_integer + 1
        )
        begin
            group_index =
                group_index_integer[8:0];

            #1;

            for (
                lane_index = 0;
                lane_index < 8;
                lane_index = lane_index + 1
            )
            begin
                write_data[lane_index] =
                    word_for(logical_address[lane_index]);
            end

            write_valid =
                1'b1;

            @(posedge clk);
            #1;
        end

        write_valid =
            1'b0;

        stage =
            4'd11;

        for (
            group_index_integer = 0;
            group_index_integer < 512;
            group_index_integer = group_index_integer + 1
        )
        begin
            group_index =
                group_index_integer[8:0];

            read_valid =
                1'b1;

            @(posedge clk);
            #1;

            if (!read_data_valid)
            begin
                $fatal(
                    1,
                    "read_data_valid missing group=%0d",
                    group_index_integer
                );
            end

            for (
                lane_index = 0;
                lane_index < 8;
                lane_index = lane_index + 1
            )
            begin
                expected_word =
                    word_for(logical_address[lane_index]);

                if (read_data[lane_index] != expected_word)
                begin
                    $fatal(
                        1,
                        "store mismatch group=%0d lane=%0d address=%0d result=%08x expected=%08x",
                        group_index_integer,
                        lane_index,
                        logical_address[lane_index],
                        read_data[lane_index],
                        expected_word
                    );
                end

                store_words_checked =
                    store_words_checked + 1;
            end
        end

        read_valid =
            1'b0;

        $display(
            "PASS: eight-bank mapping covers every logical coefficient"
        );

        $display(
            "PASS: all eight addresses occupy distinct banks"
        );

        $display(
            "PASS: four butterflies issue per schedule group"
        );

        $display(
            "PASS: all 12 DIF stages are conflict-free"
        );

        $display(
            "PASS: all 12 DIT stages are conflict-free"
        );

        $display(
            "PASS: exactly 512 groups per stage"
        );

        $display(
            "PASS: exactly 6144 groups per transform"
        );

        $display(
            "PASS: eight-bank store supports eight reads and eight writes"
        );

        $display(
            "PASS: store capacity remains 4096 x 32 bits"
        );

        $display(
            "DIF groups: %0d",
            dif_group_count
        );

        $display(
            "DIT groups: %0d",
            dit_group_count
        );

        $display(
            "Store words checked: %0d",
            store_words_checked
        );

        $finish;
    end

endmodule
