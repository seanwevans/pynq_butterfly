# Four-butterfly polynomial metadata-alignment fix

The arithmetic wrapper has a nine-clock input-to-output latency.

The previous full polynomial core captured metadata in slot 0 but consumed
slot 8, which is one clock early. A result was therefore written with the
following operation's address, phase, half-group selector, and preserved
coefficient data.

This replacement:

- expands each metadata delay array from slots 0..8 to slots 0..9
- shifts through ten entries
- consumes slot 9 with `arithmetic_output_valid`
- leaves the 22,968-cycle controller schedule unchanged

The Icarus `constant selects in always_*` messages are simulator limitations,
not functional errors.

Install and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./poly_mul4096_four_butterfly_metadata_fix.zip
./compile_poly_mul4096_four_butterfly_pipeline.sh
```
