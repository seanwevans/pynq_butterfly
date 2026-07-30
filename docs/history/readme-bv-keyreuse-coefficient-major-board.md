# Coefficient-major evaluation-key-reuse board checkpoint

The complete overlay routes:

```text
core/control:      100 MHz
DMA/HP subsystem:  150 MHz
WNS:               +0.083 ns
failing paths:     0
LUTs:              9838
registers:         9766
DSP48E1:           160
RAMB18E1:          4
RAMB36E1:          4
SRLs:              992
bitstream:         complete
HWH:               complete
```

This checkpoint installs the bitstream, exact OpenFHE vectors, and the first
coefficient-major PYNQ runner.

## Install from WSL

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_coefficient_major_board_checkpoint.zip

./scripts/board/install/install_bv_keyreuse_coefficient_major_board.sh
```

Default destination:

```text
xilinx@pynq:/home/xilinx/jupyter_notebooks/bv_keyreuse_coefficient_major
```

## Run on the PYNQ-Z2

```bash
ssh xilinx@pynq
sudo -i

/home/xilinx/jupyter_notebooks/bv_keyreuse_coefficient_major/run_bv_keyreuse_coefficient_major_board.sh \
  /home/xilinx/jupyter_notebooks/bv_keyreuse_coefficient_major \
  8 \
  5
```

Arguments:

```text
remote directory
ciphertext batch count
timed runs
```

Start with batch 8. The hardware supports batches 8 through 64.

## Exact board work

For each of six tower pairs, the runner sends one `RLPF` profile and one
coefficient-major `RLCM` transaction.

For batch 8 and twelve digits:

```text
old protocol: 320 words/coefficient
new protocol: 152 words/coefficient
reduction:     52.5%
```

Every returned `c0` and `c1` coefficient for all eight ciphertexts is checked
against the exact OpenFHE 1.5.1 result.

Host frame packing is outside the timed DMA interval. BV decomposition remains
host-side.

## Expected ending

```text
PASS: every coefficient-major RLCM result matches OpenFHE
towers=12
pairs=6
digits=12
ciphertexts=8
words_per_coefficient=152
legacy_words_per_coefficient=320
input_reduction=52.5000%
...
verified_tower_components=192
data_us_per_relinearized_EvalMult=...
data_relinearized_EvalMult_per_second=...
end_to_end_us_per_relinearized_EvalMult=...
end_to_end_relinearized_EvalMult_per_second=...
```

The serialized coefficient scheduler is expected to approach roughly:

```text
185 relinearized EvalMult/s at batch 8
```

The later two-bank overlap architecture should approach approximately 214/s at
batch 8 and 248/s at batch 64.
