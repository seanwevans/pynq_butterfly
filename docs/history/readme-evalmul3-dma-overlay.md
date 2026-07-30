# Fused evaluation-domain AXI-DMA overlay checkpoint

The standalone core has physically closed at 100 MHz:

```text
WNS        +0.165 ns
failures   0
LUTs       4,135
registers  3,673
DSP48E1    128
BRAM       0
```

This checkpoint places that core behind a 64-bit AXI DMA in a complete
PYNQ-Z2 design.

## Block design

```text
PS M_AXI_GP0
    -> SmartConnect
    -> DMA S_AXI_LITE

DMA M_AXI_MM2S
    -> SmartConnect
    -> PS S_AXI_HP0

DMA M_AXI_S2MM
    -> SmartConnect
    -> PS S_AXI_HP1

DMA M_AXIS_MM2S
    -> evalmul3 S_AXIS

evalmul3 M_AXIS
    -> DMA S_AXIS_S2MM
```

The DMA length register is configured for 26 bits, enough for the expected
multi-megabyte ciphertext batches.

## Build

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_dma_overlay_checkpoint.zip

./scripts/vivado/build_evalmul3_dma_overlay.sh
```

Default build directory:

```text
/mnt/f/v/evalmul3_dma_overlay
```

Successful deploy directory:

```text
deploy/evalmul3_two_tower_dma/
```

containing:

```text
evalmul3_two_tower_dma.bit
evalmul3_two_tower_dma.hwh
run_fpga_evalmul3.py
build_summary.txt
routed_timing_summary.rpt
routed_utilization.rpt
```

The XSA is kept outside the deploy directory under the build directory so it
cannot confuse PYNQ's `Overlay` loader.

## Board run

Generate a representative vector set first:

```bash
./openfhe_eval_domain_bridge/build/openfhe_eval_domain_bridge \
  generate \
  openfhe_eval_domain_bridge/vectors/t12_c32 \
  12 \
  32 \
  0xe1a140962026
```

Install:

```bash
./scripts/board/install/install_evalmul3_board.sh \
  openfhe_eval_domain_bridge/vectors/t12_c32
```

Copy and run the board helper:

```bash
scp run_evalmul3_board.sh xilinx@pynq:/home/xilinx/jupyter_notebooks/evalmul3/

ssh -t xilinx@pynq \
  /home/xilinx/jupyter_notebooks/evalmul3/run_evalmul3_board.sh
```

Expected target for twelve towers:

```text
approximately 983 us/ciphertext
approximately 1,017 EvalMultNoRelin/s
```

The physical result is not claimed until the board run passes exactly.
