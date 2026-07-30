# Four-wide buffered four-butterfly checkpoint

The exact eight-wide buffered design missed the 100 MHz PYNQ-Z2 constraint by
about 0.6 ns. This checkpoint halves only the result/refill handoff width.

```text
22,968 arithmetic clocks
 1,025 four-wide handoff clocks
-------------------------------
23,993 clocks/product
239.93 us/product at 100 MHz
4,167.88 products/s hardware ceiling
```

The overlap architecture is unchanged:

- one paired A/B operand prefetch buffer;
- one paired result buffer;
- input of product k+1 during computation of product k;
- result k streaming during computation of product k+1;
- exact q0/q1 OpenFHE output.

The arithmetic stores retain their proven eight-wide transform interface. Only
the idle handoff write path is reduced to four lanes and selected locally beside
the BRAM banks. Shadow and result buffers use four 1024 x 64 banks instead of
eight 512 x 64 banks, preserving capacity while halving simultaneous routing.

## Apply

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o poly_mul4096_four_butterfly_buffered4.zip
```

## Exact simulation

```bash
./scripts/synth/compile_poly_mul4096_four_butterfly_two_tower_buffered_axis.sh
```

Expected ending:

```text
PASS: 4 buffered exact two-tower OpenFHE products
PASS: four-wide result/refill handoff = 1025 clocks
PASS: operand prefetch and compute/output overlap observed
Steady hardware cadence: 23993 cycles/product
```

## Physical build

```bash
./scripts/vivado/build_poly_mul4096_four_butterfly_two_tower_buffered_board.sh
```

The board build still rejects negative routed WNS. A successful build emits:

```text
deploy/poly_mul4096_four_butterfly_two_tower_buffered_dma/
```
