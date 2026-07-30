# Batched four-butterfly two-tower overlay

This checkpoint adds `MULB` batching to the exact 22,968-cycle two-tower
multiplier already measured at 874.05 products/s with one DMA transaction per
product.

## Protocol

```text
MULB command: 0x4d554c42 in both 32-bit lanes
word 1:       batch count repeated in both lanes
then:         A[4096], B[4096] for each product
input TLAST:  final B coefficient of final product
output TLAST: final result coefficient of final product
```

MM2S and S2MM each execute one DMA transaction for the complete batch. There
is no operand prefetch or result BRAM yet; this isolates transaction
amortization before adding overlap hardware.

## 1. Install

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./poly_mul4096_four_butterfly_batch_overlay.zip
```

## 2. Simulate a two-product batch

```bash
./scripts/synth/compile_poly_mul4096_four_butterfly_two_tower_batch_axis.sh
```

Expected ending:

```text
PASS: MULB produced 2 exact two-tower OpenFHE products
PASS: checked 8192 paired output coefficients with one final TLAST
Core cycles per product: 22968
```

## 3. Build the PYNQ-Z2 overlay

```bash
./scripts/vivado/build_poly_mul4096_four_butterfly_two_tower_batch_board.sh
```

Deployment directory:

```text
deploy/poly_mul4096_four_butterfly_two_tower_batch_dma/
```

The `.xsa` is intentionally written under `reports/.../hardware_platform/`,
not beside the board `.bit` and `.hwh`.

## 4. Install and run

```bash
./scripts/board/install/install_poly_mul4096_four_butterfly_two_tower_batch_board.sh pynq
```

On the board:

```bash
cd /home/xilinx/jupyter_notebooks/p4ttb
./scripts/board/run/run_poly_mul4096_four_butterfly_two_tower_batch_board.sh
```

Optional arguments are batch-size CSV and timed runs:

```bash
./scripts/board/run/run_poly_mul4096_four_butterfly_two_tower_batch_board.sh 1,4,16,32 10
```

The launcher sources any present PYNQ/XRT profile scripts and uses the PYNQ
virtual-environment Python explicitly.
