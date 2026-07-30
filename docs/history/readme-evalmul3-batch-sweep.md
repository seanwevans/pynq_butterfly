# EvalMul3 DMA batch-scaling checkpoint

Before changing the overlay, measure whether the current 81.9% efficiency is
mostly fixed DMA transaction overhead or sustained memory-path loss.

A single 12-tower, 256-ciphertext vector set is generated. The patched board
runner can consume prefixes of 32, 64, 128, and 256 ciphertexts without
regenerating or re-uploading the files.

## Apply after committing the 833 ciphertext/s milestone

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_batch_sweep_checkpoint.zip

./scripts/archive/begin_evalmul3_dma_throughput_branch.sh
```

## Generate one maximum-size vector set

```bash
./scripts/board/install/prepare_evalmul3_batch_sweep.sh 12 256
```

The input transfer for one tower pair is approximately 32 MiB at batch 256,
which remains within the overlay's 26-bit DMA length register.

## Install

```bash
./scripts/board/install/install_evalmul3_sweep_board.sh \
  openfhe_eval_domain_bridge/vectors/t12_c256
```

## Run as root on the board

```bash
/home/xilinx/jupyter_notebooks/evalmul3/run_evalmul3_board_sweep.sh
```

The sweep performs five timed exact runs at each batch size:

```text
32
64
128
256
```

Interpretation:

- Strong improvement with batch size means fixed DMA setup/termination overhead
  dominates and the existing datapath may approach 1,000 ciphertext/s without
  another bitstream.
- A flat efficiency curve near 82% means sustained HP/DDR throughput dominates;
  the next bitstream should disable DRE, increase AXI DMA burst granularity,
  and then test a faster memory-side DMA clock.

The patched runner also asserts that every PYNQ DMA buffer address and length
is 64-bit aligned, establishing the precondition for a later no-DRE overlay.
