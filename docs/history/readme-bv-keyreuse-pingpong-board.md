# Ping-pong coefficient-major board checkpoint

The full ping-pong DMA150 overlay is physically complete:

```text
core/control:      100 MHz
DMA/HP subsystem:  150 MHz
WNS:               +0.006 ns
failing paths:     0
LUTs:              10108
registers:         10117
DSP48E1:           160
RAMB18E1:          4
RAMB36E1:          4
SRLs:              992
bitstream:         complete
HWH:               complete
```

The `RLPF` and `RLCM` protocols are unchanged. The existing exact
coefficient-major board runner is therefore reused with only the overlay and
deployment names changed.

## Install from WSL

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_pingpong_board_checkpoint.zip

./scripts/board/install/install_bv_keyreuse_pingpong_board.sh
```

Default destination:

```text
xilinx@pynq:/home/xilinx/jupyter_notebooks/bv_keyreuse_pingpong
```

## First board run

```bash
ssh xilinx@pynq
sudo -i

/home/xilinx/jupyter_notebooks/bv_keyreuse_pingpong/run_bv_keyreuse_pingpong_board.sh \
  /home/xilinx/jupyter_notebooks/bv_keyreuse_pingpong \
  8 \
  5
```

Start with batch 8. After exactness is established, sweep:

```bash
REMOTE=/home/xilinx/jupyter_notebooks/bv_keyreuse_pingpong

for b in 16 32 64; do
  "$REMOTE/run_bv_keyreuse_pingpong_board.sh" \
    "$REMOTE" \
    "$b" \
    5 | tee "$REMOTE/results/batch_${b}.log"
done
```

## Expected throughput region

The ping-pong scheduler removes the deterministic `2B` output serialization
from the steady-state coefficient schedule. Input-bound ceilings at 100 MHz
are:

```text
batch  input-bound ceiling
8      214.16/s
16     232.51/s
32     242.93/s
64     248.49/s
```

The serialized hardware measured:

```text
batch  serialized data rate
8      164.06/s
16     189.88/s
32     206.45/s
64     215.78/s
```

Every returned `c0` and `c1` residue is checked against the exact OpenFHE 1.5.1
result. Host frame packing remains outside the timed DMA interval, and BV CRT
decomposition remains host-side.
