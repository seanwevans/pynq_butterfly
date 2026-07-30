# AXI simulation progress/watchdog patch

After profile loading, the testbench performs:

```text
8,193 AXI input handshakes
22,968 arithmetic clocks
8,192 output-state clocks for 4,096 coefficients
```

That is 39,353 clocks after the last visible profile message. Icarus also
expands several `always_comb` sensitivity sets, so the two-tower simulation
can consume substantial CPU time without printing anything.

This patch:

- verifies/applies the corrected pre-edge `TREADY` handshake
- prints when product streaming begins
- prints when the complete product frame is accepted
- reports state/core/output progress every 5,000 clocks
- terminates with a detailed watchdog after 100,000 post-profile clocks

Install from the repository root:

```bash
unzip -o ./poly_mul4096_axis_tb_progress_fix.zip
./scripts/archive/apply_poly_mul4096_axis_tb_progress_fix.sh
```
