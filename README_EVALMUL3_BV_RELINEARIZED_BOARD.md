# Exact fused BV relinearization board checkpoint

The complete overlay now routes:

```text
core/control:      100 MHz
DMA/HP subsystem:  150 MHz
WNS:               +0.045 ns
failing paths:     0
LUTs:              11746
registers:         11875
DSP48E1:           192
RAMB18E1:          4
RAMB36E1:          4
bitstream:         complete
HWH:               complete
```

This checkpoint installs the bitstream, exact OpenFHE BV vectors, and a PYNQ
runner.

## Install from WSL

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_relinearized_board_checkpoint.zip

./install_evalmul3_bv_relinearized_board.sh
```

The default target is:

```text
xilinx@pynq:/home/xilinx/jupyter_notebooks/evalmul3_bv_relinearized
```

## Run on the PYNQ-Z2

```bash
ssh xilinx@pynq

/home/xilinx/jupyter_notebooks/evalmul3_bv_relinearized/run_evalmul3_bv_relinearized_board.sh \
  /home/xilinx/jupyter_notebooks/evalmul3_bv_relinearized \
  8 \
  5
```

Arguments are:

```text
remote directory
ciphertext batch count
timed runs
```

Start with batch 8. The frame limit permits at most 51 ciphertexts per
paired-tower RLBV transaction, but larger contiguous CMA buffers may require a
fresh board boot.

## What the runner does

For each of six paired Q-tower profiles, it constructs:

```text
RLPF:
    command
    paired q
    paired mu

RLBV:
    command
    {12 digits, batch count}

    for each ciphertext and coefficient:
        a0, a1, b0, b1

        for each of 12 BV digits:
            digit
            evaluation-key B
            evaluation-key A
```

The hardware returns:

```text
relinearized c0
relinearized c1
```

Every output coefficient is checked against the exact OpenFHE 1.5.1 result.

The runner reuses one CMA send buffer and one CMA receive buffer across all six
pairs. Evaluation-key data is prepared once in normal host memory and copied
into the current pair frame outside the timed DMA interval.

## Expected ending

```text
PASS: every fused RLBV relinearized component matches OpenFHE
towers=12
pairs=6
digits=12
ciphertexts=8
...
verified_tower_components=192
data_us_per_relinearized_EvalMult=...
data_relinearized_EvalMult_per_second=...
end_to_end_us_per_relinearized_EvalMult=...
end_to_end_relinearized_EvalMult_per_second=...
```

`data_*` measures the six RLBV DMA transactions. `end_to_end_*` additionally
includes the six required profile loads. Host-side vector packing and BV CRT
decomposition are not included.

The input-limited ideal at 100 MHz is:

```text
6 pairs * 4096 coefficients * 40 words = 983040 cycles/ciphertext
ideal data latency = 9830.4 us/ciphertext
ideal data rate = 101.725 relinearized EvalMult/s
```
