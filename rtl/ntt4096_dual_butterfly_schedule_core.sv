`timescale 1ns/1ps

module ntt4096_dual_butterfly_schedule_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,
    input  logic        descending,
    output logic        busy,
    output logic        valid,
    output logic        done,
    output logic [3:0]  stage_bit,
    output logic [9:0]  pair_index,
    output logic [11:0] address0_a,
    output logic [11:0] address0_b,
    output logic [11:0] address1_a,
    output logic [11:0] address1_b,
    output logic [10:0] twiddle_index0,
    output logic [10:0] twiddle_index1
);

    logic [3:0] current_stage;
    logic [9:0] current_pair;
    logic       current_descending;

    wire [3:0] companion_stage_bit =
        current_stage < 4'd11
            ? current_stage + 1'b1
            : 4'd10;

    function automatic [11:0] deposit_pair_index;
        input [9:0] packed_index;
        input [3:0] skip_bit0;
        input [3:0] skip_bit1;
        integer destination_bit;
        integer source_bit;
        begin
            deposit_pair_index = 12'd0;
            source_bit = 0;
            for (destination_bit = 0; destination_bit < 12; destination_bit = destination_bit + 1) begin
                if (destination_bit != skip_bit0 && destination_bit != skip_bit1) begin
                    deposit_pair_index[destination_bit] = packed_index[source_bit];
                    source_bit = source_bit + 1;
                end
            end
        end
    endfunction

    wire [11:0] current_base =
        deposit_pair_index(current_pair, current_stage, companion_stage_bit);

    wire [11:0] current_second_base =
        current_base | (12'd1 << companion_stage_bit);

    wire [11:0] current_address0_a = current_base;
    wire [11:0] current_address0_b = current_base | (12'd1 << current_stage);
    wire [11:0] current_address1_a = current_second_base;
    wire [11:0] current_address1_b = current_second_base | (12'd1 << current_stage);

    wire [10:0] current_twiddle_index0 =
        current_stage == 0
            ? 11'd0
            : current_address0_a[10:0] & ((11'd1 << current_stage) - 1'b1);

    wire [10:0] current_twiddle_index1 =
        current_stage == 0
            ? 11'd0
            : current_address1_a[10:0] & ((11'd1 << current_stage) - 1'b1);

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            busy <= 1'b0;
            valid <= 1'b0;
            done <= 1'b0;
            current_stage <= 4'd0;
            current_pair <= 10'd0;
            current_descending <= 1'b0;
            stage_bit <= 4'd0;
            pair_index <= 10'd0;
            address0_a <= 12'd0;
            address0_b <= 12'd0;
            address1_a <= 12'd0;
            address1_b <= 12'd0;
            twiddle_index0 <= 11'd0;
            twiddle_index1 <= 11'd0;
        end else begin
            valid <= 1'b0;
            done <= 1'b0;

            if (start && !busy) begin
                busy <= 1'b1;
                current_descending <= descending;
                current_stage <= descending ? 4'd11 : 4'd0;
                current_pair <= 10'd0;
            end else if (busy) begin
                valid <= 1'b1;
                stage_bit <= current_stage;
                pair_index <= current_pair;
                address0_a <= current_address0_a;
                address0_b <= current_address0_b;
                address1_a <= current_address1_a;
                address1_b <= current_address1_b;
                twiddle_index0 <= current_twiddle_index0;
                twiddle_index1 <= current_twiddle_index1;

                if (current_pair == 10'd1023) begin
                    current_pair <= 10'd0;
                    if ((current_descending && current_stage == 0) ||
                        (!current_descending && current_stage == 4'd11)) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else if (current_descending) begin
                        current_stage <= current_stage - 1'b1;
                    end else begin
                        current_stage <= current_stage + 1'b1;
                    end
                end else begin
                    current_pair <= current_pair + 1'b1;
                end
            end
        end
    end
endmodule
