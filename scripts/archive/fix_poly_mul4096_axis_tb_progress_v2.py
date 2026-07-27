#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys


def main() -> int:
    repo = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    path = repo / "rtl" / "tb_poly_mul4096_four_butterfly_two_tower_axis_core.sv"

    if not path.is_file():
        raise RuntimeError(f"testbench not found: {path}")

    text = path.read_text(encoding="utf-8")

    if "integer post_profile_cycles;" not in text:
        match = re.search(
            r"(?m)^(\s*integer\s+received_coefficients\s*;\s*)$",
            text,
        )
        if not match:
            raise RuntimeError(
                "could not find received_coefficients declaration"
            )

        text = (
            text[:match.end()]
            + "\n    integer post_profile_cycles;"
            + text[match.end():]
        )

    if re.search(
        r"post_profile_cycles\s*=\s*0\s*;",
        text,
    ) is None:
        match = re.search(
            r"received_coefficients\s*=\s*0\s*;",
            text,
        )
        if not match:
            raise RuntimeError(
                "could not find received_coefficients initialization"
            )

        text = (
            text[:match.end()]
            + "\n\n        post_profile_cycles =\n            0;"
            + text[match.end():]
        )

    marker = "AXI PROGRESS clocks=%0d"

    if marker not in text:
        clock = re.search(
            r"(?ms)^(\s*always\s*#5\s+clk\s*=\s*~clk\s*;)",
            text,
        )

        if not clock:
            raise RuntimeError(
                "could not locate clock generator with regex"
            )

        monitor = r'''

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
'''

        text = text[:clock.end()] + monitor + text[clock.end():]

    if "START: sending 8193-word paired product frame" not in text:
        profile_message = re.search(
            r'(?ms)\$display\s*\(\s*"PASS: AXI profile frame loaded both towers"\s*\)\s*;',
            text,
        )

        if not profile_message:
            raise RuntimeError(
                "could not find profile-loaded display"
            )

        addition = r'''

        $display(
            "START: sending 8193-word paired product frame"
        );
'''
        text = (
            text[:profile_message.end()]
            + addition
            + text[profile_message.end():]
        )

    accepted_message = (
        "PASS: paired product frame accepted; waiting for "
        "22968-cycle core and 4096 outputs"
    )

    if accepted_message not in text:
        output_loop = re.search(
            r"(?m)^\s*while\s*\(\s*received_coefficients\s*<\s*N\s*\)",
            text,
        )

        if not output_loop:
            raise RuntimeError(
                "could not find output collection loop"
            )

        addition = r'''
        $display(
            "PASS: paired product frame accepted; waiting for 22968-cycle core and 4096 outputs"
        );

'''
        text = text[:output_loop.start()] + addition + text[output_loop.start():]

    if "while (!s_axis_tready)" not in text:
        raise RuntimeError(
            "corrected send_word handshake is missing; "
            "apply the handshake fix first"
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
