# Shared-A/B four-butterfly NTT checkpoint

This checkpoint proves the resource-feasible NTT geometry for the exact
two-tower OpenFHE polynomial multiplier.

Each RNS tower receives one four-lane NTT engine. That engine is time-multiplexed
across:

1. forward DIF on operand A
2. forward DIF on operand B
3. inverse DIT on result A

The two-tower projection is 128 DSP48E1 blocks. Duplicating engines for A and B
would require 256 DSP48E1 blocks and cannot fit the XC7Z020's 220 blocks.

Expected single-tower checkpoint:

- 3 transforms
- 18,831 clocks
- 64 DSP48E1
- 16 RAMB18E1 for A/B coefficient stores
- 16 RAMB36E1 for four-read forward/inverse twiddle tables
- 100 MHz routed timing

## Install from WSL

Place this ZIP in the repository root:

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./ntt4096_shared_ab_pipeline_checkpoint.zip
```

The drop adds uniquely named files and does not replace the routed standalone
NTT checkpoint.

## Functional gate

```bash
./compile_ntt4096_four_butterfly_shared_ab.sh
```

Expected ending:

```text
PASS: tower 0 A roundtrip and B forward spectrum match exactly
PASS: tower 1 A roundtrip and B forward spectrum match exactly
PASS: shared four-lane engine completed 6 transforms and checked 16384 coefficients
PASS: each tower sequence completed in 18831 cycles
```

## Routed implementation

```bash
./implement_ntt4096_four_butterfly_shared_ab.sh
./check_ntt4096_four_butterfly_shared_ab.py
```

## Complete sequence

```bash
./run_ntt4096_four_butterfly_shared_ab_all.sh
```

After this checkpoint passes, the next splice preserves the old iterative
twist, pointwise, and postscale phases while replacing the old paired
forward/inverse NTT states with this shared four-lane engine.
