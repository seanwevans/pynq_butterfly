#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


def main() -> int:
    repo = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    path = repo / "rtl" / "tb_poly_mul4096_four_butterfly_two_tower_axis_core.sv"

    if not path.is_file():
        raise RuntimeError(f"testbench not found: {path}")

    text = path.read_text(encoding="utf-8")

    old_task = '''    task automatic send_word (
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
'''

    new_task = '''    /*
     * Hold TVALID until a rising edge on which TREADY is already high.
     * The receiver may deassert TREADY immediately after accepting a word,
     * so checking TREADY after that edge loses the handshake event.
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
'''

    if old_task not in text:
        if new_task in text:
            print("PASS: AXI testbench handshake fix already applied")
            return 0
        raise RuntimeError("expected send_word task was not found")

    path.write_text(text.replace(old_task, new_task, 1), encoding="utf-8", newline="\n")
    print(f"PASS: patched {path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
