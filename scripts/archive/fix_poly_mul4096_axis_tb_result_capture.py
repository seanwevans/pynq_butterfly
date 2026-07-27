#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys


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

    task_pattern = re.compile(
        r"(?ms)^\s*task\s+automatic\s+send_word\s*\("
        r".*?^\s*endtask\s*$"
    )

    task_match = task_pattern.search(text)
    if not task_match:
        raise RuntimeError("could not find complete send_word task")

    corrected_task = r"""
    /*
     * Drive before the accepting edge and sample TREADY only before that
     * edge. The receiver may legally deassert TREADY immediately after
     * accepting the final word.
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

            @(negedge clk);

            while (!s_axis_tready)
            begin
                @(negedge clk);
            end

            @(posedge clk);
            #1;

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;
        end
    endtask
"""

    text = (
        text[:task_match.start()]
        + corrected_task
        + text[task_match.end():]
    )

    ready_high = re.compile(
        r"m_axis_tready\s*=\s*1'b1\s*;"
    )

    ready_low = re.compile(
        r"m_axis_tready\s*=\s*1'b0\s*;"
    )

    if ready_high.search(text):
        text = ready_high.sub(
            "m_axis_tready =\n            1'b0;",
            text,
            count=1,
        )
    elif not ready_low.search(text):
        raise RuntimeError("could not find m_axis_tready initialization")

    accepted_pattern = re.compile(
        r'(?ms)\$display\s*\(\s*'
        r'"PASS: paired product frame accepted; waiting for '
        r'22968-cycle core and 4096 outputs"\s*'
        r'\)\s*;'
    )

    accepted_match = accepted_pattern.search(text)
    if not accepted_match:
        raise RuntimeError(
            "could not find paired-product accepted display"
        )

    nearby = text[
        accepted_match.end():
        accepted_match.end() + 600
    ]

    if not re.search(
        r"m_axis_tready\s*=\s*1'b1\s*;",
        nearby,
    ):
        release = r"""

        /*
         * The core may already be presenting coefficient zero. Releasing
         * TREADY here preserves it until the checking loop observes the
         * first rising-edge handshake.
         */
        m_axis_tready =
            1'b1;
"""

        text = (
            text[:accepted_match.end()]
            + release
            + text[accepted_match.end():]
        )

    path.write_text(
        text,
        encoding="utf-8",
        newline="\n",
    )

    print(
        "PASS: replaced send_word and enabled lossless result capture"
    )
    print(f"PASS: patched {path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
