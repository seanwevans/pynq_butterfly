# Clean AXI testbench replacement

This replaces the patched testbench rather than modifying it again.

The output checker runs concurrently from reset and validates every AXI output
handshake immediately. The stimulus thread only sends profile/product frames
and waits for `output_complete`.

It also reports progress while loading the 16,385-word profile, sending both
4,096-coefficient operands, computing, and receiving results.

Apply from the repository root:

```bash
unzip -o ./poly_mul4096_axis_tb_clean_replacement.zip
./scripts/archive/install_poly_mul4096_axis_tb_clean_replacement.sh
```
