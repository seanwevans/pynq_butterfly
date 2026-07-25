# AXI testbench progress patch v2

This version uses regular expressions rather than exact whitespace matching,
so it works after the earlier handshake patch changed the testbench formatting.

From the repository root:

```bash
unzip -o ./poly_mul4096_axis_tb_progress_fix_v2.zip
./apply_poly_mul4096_axis_tb_progress_fix_v2.sh
```
