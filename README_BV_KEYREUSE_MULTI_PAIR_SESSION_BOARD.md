# Persistent-output multi-pair board checkpoint

The full DMA150 overlay is physically complete:

```text
core/control:      100 MHz
DMA/HP subsystem:  150 MHz
WNS:               +0.040 ns
failing paths:     0
LUTs:              11084
registers:         11488
DSP48E1:           160
RAMB18E1:          4
RAMB36E1:          4
SRLs:              992
bitstream:         complete
HWH:               complete
```

Exact simulation already proved:

```text
3072 exact output words
5 intermediate child TLAST markers suppressed
400 deterministic output-backpressure cycles
zero mismatches
```

## DMA session

The runner loads all six profiles once with `RLPT`.

For each benchmark session it:

```text
arms one S2MM transfer for all six pair outputs
submits six independently sized RLMP MM2S frames
waits for S2MM only after pair 5
checks every c0/c1 residue against OpenFHE
```

This keeps B64 pair inputs below the 26-bit DMA limit while reducing S2MM
transactions from six to one.

The primary `dma_active_us` metric includes:

```text
one S2MM setup
six MM2S transfer-and-wait intervals
the final S2MM completion tail
```

Python frame packing is excluded. `session_wall_us` is also reported and
includes host preparation of pairs 1 through 5.

## Install

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_multi_pair_session_board_checkpoint.zip

./scripts/board/install/install_bv_keyreuse_multi_pair_session_board.sh
```

## First board run

```bash
ssh xilinx@pynq
sudo -i

/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session/run_bv_keyreuse_multi_pair_session_board.sh \
  /home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session \
  8 \
  5
```

After exact B8:

```bash
REMOTE=/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session

for b in 16 32 64; do
  echo
  echo "===== MULTI-PAIR SESSION BATCH $b ====="

  "$REMOTE/run_bv_keyreuse_multi_pair_session_board.sh" \
    "$REMOTE" \
    "$b" \
    5 | tee "$REMOTE/results/batch_${b}.log"
done
```

Input-bound ceilings remain approximately:

```text
B8    214.15/s
B16   232.50/s
B32   242.93/s
B64   248.49/s
```

The prior six-S2MM drain-overlap result at B64 was:

```text
262915.04 us per 64 ciphertexts
243.42/s
```

Reaching the measured OpenFHE reference of roughly 244.9/s requires reducing
that run by only about 1.55 ms.
