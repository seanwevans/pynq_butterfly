# Eight-wide buffered four-butterfly checkpoint

This checkpoint adds the next pipeline layer to the exact 22,968-cycle
four-butterfly two-tower core:

- one complete paired A/B shadow operand buffer;
- one complete paired result buffer;
- 8 coefficients per clock copied out of the arithmetic store;
- 8 paired A and B coefficients per clock refilled into the arithmetic store;
- continuous `MULB` input with MM2S backpressure only when the one-product
  shadow buffer is full;
- result streaming concurrent with the next arithmetic product.

The expected steady cadence is:

```text
22,968 arithmetic clocks
   513 eight-wide handoff clocks
-------------------------------
23,481 clocks/product
234.81 us/product at 100 MHz
4,258.76 products/s hardware ceiling
```

## Install

```bash
cd /mnt/f/repos/pynq_butterfly
git switch four-butterfly-buffered-overlap
unzip -o ./poly_mul4096_four_butterfly_buffered8.zip
```

## Simulate

```bash
./scripts/synth/compile_poly_mul4096_four_butterfly_two_tower_buffered_axis.sh
```

Expected ending:

```text
PASS: 4 buffered exact two-tower OpenFHE products
PASS: eight-wide result/refill handoff = 513 clocks
PASS: operand prefetch and compute/output overlap observed
Steady hardware cadence: 23481 cycles/product
```

The implementation script derives the handoff-capable arithmetic core from the
already committed exact core. It does not modify the proven source file.
Board packaging is intentionally held until this exact concurrent simulation
passes.
