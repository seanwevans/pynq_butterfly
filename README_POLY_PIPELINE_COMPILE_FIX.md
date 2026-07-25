# Four-butterfly polynomial compile fix

This replacement fixes the first Icarus compile gate:

- removes enum-typed old-style task ports rejected at lines 1022 and 1039
- writes all controller phase transitions inline
- removes the truncated `10'd1024` constant
- compares the 10-bit linear write counter directly against terminal count 1023
- compares the NTT stage write counter against terminal count 511

Install from WSL:

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./poly_mul4096_four_butterfly_compile_fix.zip
./compile_poly_mul4096_four_butterfly_pipeline.sh
```
