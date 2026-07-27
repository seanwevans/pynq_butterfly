# Prepacked multi-pair board-runner fix

The first persistent-output board run proved exact FPGA behavior and reduced the
DMA-call interval:

```text
previous six-S2MM B8 data time: 42703.14 us
persistent-output dma_call_us:  40548.00 us
improvement:                     2155.14 us
throughput:                      187.34/s -> 197.30/s
```

However, the runner packed pairs 1 through 5 with nested Python loops while the
persistent S2MM transfer was active. That created a roughly 32-second session
wall time:

```text
median_dma_call_us=40548.00
median_session_wall_us=32187591.61
```

This was a host-runner defect, not FPGA latency.

## Fix

Pair frames are now constructed with NumPy broadcasted views before the timed
session.

The default `--send-buffer-mode auto`:

```text
1. tries one prefilled CMA MM2S buffer per pair;
2. falls back to prepacked normal arrays plus one reusable CMA buffer if the
   all-CMA allocation does not fit.
```

`all-cma` performs no frame packing or copying while S2MM is active. This is
the preferred benchmark mode.

`reuse-copy` performs only vectorized `np.copyto` plus cache flush during the
session and reports that cost separately.

New metrics:

```text
send_buffer_mode
prepack_us
dma_call_us
session_wall_us
copy_flush_us
dispatch_gap_us
```

The primary end-to-end accelerator metric is now `session_wall_us`, not the
sum of selected DMA API calls.

## Apply

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_multi_pair_session_prepacked_board_fix.zip

./scripts/board/install/install_bv_keyreuse_multi_pair_session_board.sh
```

## Run B8

```bash
ssh xilinx@pynq
sudo -i

/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session/run_bv_keyreuse_multi_pair_session_board.sh \
  /home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session \
  8 \
  5
```

Expected mode at B8:

```text
send_buffer_mode=all-cma
median_copy_flush_us=0.00
```

For B64, a fresh reboot gives the best chance of allocating six 34.34 MB CMA
send buffers plus the 25.17 MB receive buffer. The runner automatically falls
back to `reuse-copy` if that allocation fails.
