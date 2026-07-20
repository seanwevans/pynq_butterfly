module ntt4096_four_butterfly_schedule_core (
    input  logic [3:0]       stage,
    input  logic [8:0]       group_index,
    output logic [7:0][11:0] address
);

    logic [3:0] stage_bit;
    logic [3:0] group_bit0;
    logic [3:0] group_bit1;

    logic [11:0] base_address;
    logic [11:0] stage_mask;
    logic [11:0] group_mask0;
    logic [11:0] group_mask1;

    integer logical_bit;
    integer source_bit;

    always_comb
    begin
        stage_bit =
            stage;

        group_bit0 =
            4'd0;

        group_bit1 =
            4'd0;

        case (stage)
            4'd0:
            begin
                group_bit0 = 4'd1;
                group_bit1 = 4'd2;
            end

            4'd1:
            begin
                group_bit0 = 4'd0;
                group_bit1 = 4'd2;
            end

            4'd2:
            begin
                group_bit0 = 4'd0;
                group_bit1 = 4'd1;
            end

            4'd3:
            begin
                group_bit0 = 4'd4;
                group_bit1 = 4'd5;
            end

            4'd4:
            begin
                group_bit0 = 4'd3;
                group_bit1 = 4'd5;
            end

            4'd5:
            begin
                group_bit0 = 4'd3;
                group_bit1 = 4'd4;
            end

            4'd6:
            begin
                group_bit0 = 4'd7;
                group_bit1 = 4'd8;
            end

            4'd7:
            begin
                group_bit0 = 4'd6;
                group_bit1 = 4'd8;
            end

            4'd8:
            begin
                group_bit0 = 4'd6;
                group_bit1 = 4'd7;
            end

            4'd9:
            begin
                group_bit0 = 4'd10;
                group_bit1 = 4'd11;
            end

            4'd10:
            begin
                group_bit0 = 4'd9;
                group_bit1 = 4'd11;
            end

            default:
            begin
                group_bit0 = 4'd9;
                group_bit1 = 4'd10;
            end
        endcase

        base_address =
            12'd0;

        source_bit =
            0;

        for (
            logical_bit = 0;
            logical_bit < 12;
            logical_bit = logical_bit + 1
        )
        begin
            if (
                (logical_bit != stage_bit)
                && (logical_bit != group_bit0)
                && (logical_bit != group_bit1)
            )
            begin
                base_address[logical_bit] =
                    group_index[source_bit];

                source_bit =
                    source_bit + 1;
            end
        end

        stage_mask =
            12'b1 << stage_bit;

        group_mask0 =
            12'b1 << group_bit0;

        group_mask1 =
            12'b1 << group_bit1;

        address[0] =
            base_address;

        address[1] =
            base_address
            ^ stage_mask;

        address[2] =
            base_address
            ^ group_mask0;

        address[3] =
            base_address
            ^ group_mask0
            ^ stage_mask;

        address[4] =
            base_address
            ^ group_mask1;

        address[5] =
            base_address
            ^ group_mask1
            ^ stage_mask;

        address[6] =
            base_address
            ^ group_mask0
            ^ group_mask1;

        address[7] =
            base_address
            ^ group_mask0
            ^ group_mask1
            ^ stage_mask;
    end

endmodule
