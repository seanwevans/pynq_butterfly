# Two-tower four-butterfly checkpoint

This checkpoint duplicates the proven one-tower 22,968-cycle polynomial core
for simultaneous q0/q1 execution.

It deliberately excludes AXI, operand prefetch, and result buffering. The
purpose is to answer the physical question created by the one-tower
`+0.028 ns` result:

> Can both exact OpenFHE towers fit and close 100 MHz together?

Expected resources:

```text
DSP48E1:  128
RAMB18E1: 32
RAMB36E1: 64
```

## Install

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./poly_mul4096_four_butterfly_two_tower_checkpoint.zip
```

## Functional gate

```bash
./scripts/synth/compile_poly_mul4096_four_butterfly_two_tower.sh
```

Expected ending:

```text
PASS: two towers completed exact OpenFHE product in 22968 cycles
PASS: checked 8192 paired coefficients
```

## Physical gate

```bash
./scripts/synth/implement_poly_mul4096_four_butterfly_two_tower.sh
./scripts/sim/check_poly_mul4096_four_butterfly_two_tower.py
```

After this closes timing, the final board checkpoint adds the existing paired
64-bit AXI protocol, one-product operand prefetch, one-product result buffer,
IP packaging, block-design integration, bitstream export, and exact PYNQ board
benchmark.
