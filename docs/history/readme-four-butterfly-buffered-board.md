# Buffered four-butterfly PYNQ-Z2 board checkpoint

This packages the exact eight-wide buffered-overlap simulation checkpoint as a
64-bit AXI-DMA PYNQ-Z2 overlay.

## Architecture

- exact q0/q1 OpenFHE N=4096 multiplication;
- 22,968 arithmetic clocks per product;
- one paired A/B operand prefetch buffer;
- one paired result buffer;
- 513-clock eight-wide result/refill handoff;
- 23,481-clock steady hardware cadence;
- 234.81 us/product and 4,258.76 products/s ideal at 100 MHz.

## Install source drop

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o poly_mul4096_four_butterfly_buffered_board.zip
```

## Re-run exact simulation

```bash
./scripts/synth/compile_poly_mul4096_four_butterfly_two_tower_buffered_axis.sh
```

## Build physical overlay

```bash
./scripts/vivado/build_poly_mul4096_four_butterfly_two_tower_buffered_board.sh
```

The build fails deliberately when routed WNS is negative.

Expected deployment directory:

```text
deploy/poly_mul4096_four_butterfly_two_tower_buffered_dma/
```

The XSA is written under `reports/.../hardware_platform/` so PYNQ does not
confuse it with the deploy-time `.bit` and `.hwh`.

## Install on PYNQ-Z2

```bash
./scripts/board/install/install_poly_mul4096_four_butterfly_two_tower_buffered_board.sh pynq
```

## Run physical benchmark

```bash
ssh xilinx@pynq
cd /home/xilinx/jupyter_notebooks/p4ttbo
sudo -i
cd /home/xilinx/jupyter_notebooks/p4ttbo
./scripts/board/run/run_poly_mul4096_four_butterfly_two_tower_buffered_board.sh
```

Custom batch sweep:

```bash
./scripts/board/run/run_poly_mul4096_four_butterfly_two_tower_buffered_board.sh 1,4,16,32 10
```
