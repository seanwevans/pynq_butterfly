# EvalMul3 150 MHz memory-side checkpoint

The batch sweep showed that the current 100 MHz single-clock overlay approaches
about 964 ciphertexts/s, not the 1017 ciphertexts/s stream ceiling.

This checkpoint changes only the transport architecture:

```text
100 MHz:
  PS GP0 control
  EvalMul3 arithmetic core

150 MHz:
  AXI DMA memory channels
  PS HP0 and HP1
  memory SmartConnects

CDC:
  DMA MM2S 150 MHz -> 1024-word async FIFO -> core 100 MHz
  core 100 MHz -> 1024-word async FIFO -> DMA S2MM 150 MHz
```

DMA changes:

```text
MM2S DRE     disabled
S2MM DRE     disabled
MM2S burst   16 beats
S2MM burst   16 beats
```

Burst length stays at 16 because Zynq-7000 HP ports accept at most 16 data
beats. The purpose of the faster memory domain is to refill the CDC FIFO faster
than the core consumes it, masking DDR/HP service gaps.

## Build

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_dma150_checkpoint.zip

./build_evalmul3_dma150_overlay.sh
```

Expected deploy directory:

```text
deploy/evalmul3_two_tower_dma150/
```

## Install the existing batch-256 vectors

```bash
./install_evalmul3_dma150_board.sh \
  openfhe_eval_domain_bridge/vectors/t12_c256
```

## Run on the board as root

```bash
/home/xilinx/jupyter_notebooks/evalmul3_dma150/run_evalmul3_dma150_board.sh
```

The physical target is at least:

```text
1000 EvalMultNoRelin/s compute
```

The architectural ceiling remains:

```text
1017.25 EvalMultNoRelin/s
```

No performance claim is made until exact board validation passes.
