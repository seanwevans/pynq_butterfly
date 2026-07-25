# Four-butterfly scalar-phase read/modify/write hazard fix

The four arithmetic lanes update four coefficients at a time, while the
eight-bank coefficient store writes a complete eight-coefficient group.

The previous issue order alternated halves:

```text
group 0 lower
group 0 upper
group 1 lower
group 1 upper
...
```

Both reads occurred before either result returned. Consequently, the
upper-half write preserved and restored the stale lower half, erasing the
lower-half result. The same corruption affected twist, pointwise, and
postscale.

This replacement uses:

```text
groups 0..511 lower halves
groups 0..511 upper halves
```

The matching lower-half write has completed long before an upper half is read.

Properties unchanged:

- 1,024 scalar vectors per scalar phase
- four modular multiplications per vector
- 22,968-cycle product-controller target
- 64 DSP48E1
- no additional storage

Install and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./poly_mul4096_four_butterfly_linear_hazard_fix.zip
./compile_poly_mul4096_four_butterfly_pipeline.sh
```
