# Four-butterfly pipelined N=4096 polynomial checkpoint

This checkpoint performs a complete one-tower exact negacyclic product in:

```text
Z_q[X] / (X^4096 + 1)
```

The same four Barrett multiplier pipelines are reused for:

1. twist A
2. twist B
3. forward DIF A
4. forward DIF B
5. pointwise A * B
6. inverse DIT A
7. inverse scale A

Scalar multiplication is encoded as an inverse butterfly with `a=0`, so no
additional multiplier bank is required.

Expected physical resources:

- 64 DSP48E1
- 16 RAMB18E1 for two eight-bank coefficient stores
- 32 RAMB36E1 for four four-read runtime profile tables
- two-tower DSP projection: 128 of 220

## Install from WSL

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./poly_mul4096_four_butterfly_pipeline_checkpoint.zip
```

## Functional OpenFHE gate

```bash
./compile_poly_mul4096_four_butterfly_pipeline.sh
```

This checks q0 and q1 coefficient-for-coefficient against the existing exact
OpenFHE vectors and reports the measured constant cycle count. The regression
requires fewer than 25,000 clocks versus the 631,810-clock legacy core.

## Routed implementation

```bash
./implement_poly_mul4096_four_butterfly_pipeline.sh
./check_poly_mul4096_four_butterfly_pipeline.py
```

## Complete sequence

```bash
./run_poly_mul4096_four_butterfly_pipeline_all.sh
```

The next checkpoint duplicates this proven tower core for q0/q1 parallel
execution, then reconnects the existing buffered/prefetch AXI wrapper.
