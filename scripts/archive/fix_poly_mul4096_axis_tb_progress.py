#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise RuntimeError(f"could not find {label}")
    return text.replace(old, new, 1)


def main() -> int:
    repo = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    path = (
        repo
        / "rtl"
        / "tb_poly_mul4096_four_butterfly_two_tower_axis_core.sv"
    )

    if not path.is_file():
        raise RuntimeError(f"testbench not found: {path}")

    text = path.read_text(encoding="utf-8")

    # Ensure the corrected pre-edge TREADY handshake is present.
    old_task = """    task automatic send_word (
        input logic [63:0] data,
        input logic last
    );
        begin
            s_axis_tdata =
                data;

            s_axis_tvalid =
                1'b1;

            s_axis_tlast =
                last;

            do
            begin
                @(posedge clk);
                @(negedge clk);
            end
            while (!s_axis_tready);

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;
        end
    endtask
"""

    fixed_task = """    /*
     * Hold TVALID until TREADY is high before the accepting rising edge.
     * TREADY may legally fall immediately after that edge.
     */
    task automatic send_word (
        input logic [63:0] data,
        input logic last
    );
        begin
            s_axis_tdata =
                data;

            s_axis_tvalid =
                1'b1;

            s_axis_tlast =
                last;

            while (!s_axis_tready)
            begin
                @(negedge clk);
            end

            @(posedge clk);
            @(negedge clk);

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;
        end
    endtask
"""

    if old_task in text:
        text = text.replace(old_task, fixed_task, 1)
    elif "while (!s_axis_tready)" not in text:
        raise RuntimeError("corrected send_word handshake is not present")

    declaration_anchor = """    integer address;
    integer received_coefficients;
"""

    declarations = """    integer address;
    integer received_coefficients;
    integer post_profile_cycles;
"""

    text = replace_once(
        text,
        declaration_anchor,
        declarations,
        "testbench integer declarations",
    )

    clock_anchor = """    always #5 clk =
        ~clk;

"""

    progress_block = """    always #5 clk =
        ~clk;

    /*
     * Icarus expands several always_comb sensitivity sets in this design,
     * making the two-tower simulation CPU-heavy. Report forward progress
     * and fail deterministically on a real deadlock.
     */
    always @(posedge clk)
    begin
        if (!reset_n || !profile_ready)
        begin
            post_profile_cycles <=
                0;
        end
        else
        begin
            post_profile_cycles <=
                post_profile_cycles + 1;

            if (
                post_profile_cycles != 0
                && post_profile_cycles % 5000 == 0
            )
            begin
                $display(
                    "AXI PROGRESS clocks=%0d state=%0d core_busy=%0b core_cycles0=%0d core_cycles1=%0d outputs=%0d",
                    post_profile_cycles,
                    dut.state,
                    dut.core_busy,
                    core_cycles_lane0,
                    core_cycles_lane1,
                    received_coefficients
                );
            end

            if (post_profile_cycles > 100000)
            begin
                $fatal(
                    1,
                    "AXI watchdog state=%0d core_busy=%0b core_done=%0b core_cycles0=%0d core_cycles1=%0d outputs=%0d",
                    dut.state,
                    dut.core_busy,
                    dut.core_done,
                    core_cycles_lane0,
                    core_cycles_lane1,
                    received_coefficients
                );
            end
        end
    end

"""

    text = replace_once(
        text,
        clock_anchor,
        progress_block,
        "clock generator",
    )

    init_anchor = """        received_coefficients =
            0;

        repeat (8)
"""

    init_new = """        received_coefficients =
            0;

        post_profile_cycles =
            0;

        repeat (8)
"""

    text = replace_once(
        text,
        init_anchor,
        init_new,
        "progress counter initialization",
    )

    profile_print_anchor = """        $display(
            "PASS: AXI profile frame loaded both towers"
        );

        send_word(
"""

    profile_print_new = """        $display(
            "PASS: AXI profile frame loaded both towers"
        );

        $display(
            "START: sending 8193-word paired product frame"
        );

        send_word(
"""

    text = replace_once(
        text,
        profile_print_anchor,
        profile_print_new,
        "product-frame start print",
    )

    after_b_loop_anchor = """        for (
            address = 0;
            address < N;
            address = address + 1
        )
        begin
            send_word(
                {
                    tower1_b[address],
                    tower0_b[address]
                },
                address == N - 1
            );
        end

        while (received_coefficients < N)
"""

    after_b_loop_new = """        for (
            address = 0;
            address < N;
            address = address + 1
        )
        begin
            send_word(
                {
                    tower1_b[address],
                    tower0_b[address]
                },
                address == N - 1
            );
        end

        $display(
            "PASS: paired product frame accepted; waiting for 22968-cycle core and 4096 outputs"
        );

        while (received_coefficients < N)
"""

    text = replace_once(
        text,
        after_b_loop_anchor,
        after_b_loop_new,
        "post-product-frame progress print",
    )

    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"PASS: patched {path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
