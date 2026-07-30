# Compute-drain-overlap board checkpoint

The full drain-overlap DMA150 overlay is physically complete:

```text
core/control:      100 MHz
DMA/HP subsystem:  150 MHz
WNS:               +0.008 ns
failing paths:     0
LUTs:              10143
registers:         10107
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
1581 simultaneous input/output handshakes
930 next-input/prior-bank-drain overlap handshakes
zero mismatches
```

The external `RLPF` and `RLCM` protocols are unchanged.

## Install from WSL

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_drain_overlap_board_checkpoint.zip

./scripts/board/install/install_bv_keyreuse_drain_overlap_board.sh
```

Default destination:

```text
xilinx@pynq:/home/xilinx/jupyter_notebooks/bv_keyreuse_drain_overlap
```

## First board run

```bash
ssh xilinx@pynq
sudo -i

/home/xilinx/jupyter_notebooks/bv_keyreuse_drain_overlap/run_bv_keyreuse_drain_overlap_board.sh \
  /home/xilinx/jupyter_notebooks/bv_keyreuse_drain_overlap \
  8 \
  5
```

After exact batch 8, sweep all larger batches:

```bash
REMOTE=/home/xilinx/jupyter_notebooks/bv_keyreuse_drain_overlap

for b in 16 32 64; do
  echo
  echo "===== DRAIN-OVERLAP BATCH $b ====="

  "$REMOTE/run_bv_keyreuse_drain_overlap_board.sh" \
    "$REMOTE" \
    "$b" \
    5 | tee "$REMOTE/results/batch_${b}.log"
done
```

## Input-bound ceilings

```text
batch  ceiling
8      214.16/s
16     232.51/s
32     242.93/s
64     248.49/s
```

The runner now reports:

```text
input_bound_relinearized_EvalMult_per_second
input_stream_efficiency
overhead_above_input_floor_us
verified_residue_words
```

The obsolete serialized-schedule efficiency field has been removed.

Every returned `c0` and `c1` residue is checked against the exact OpenFHE 1.5.1
result. Host frame packing remains outside the timed DMA interval, and BV CRT
decomposition remains host-side.
