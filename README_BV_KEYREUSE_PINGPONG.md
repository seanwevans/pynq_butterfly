# Ping-pong coefficient-major evaluation-key reuse

The serialized coefficient-major board sweep reached:

```text
batch  data rate   serialized efficiency
8      164.06/s    88.70%
16     189.88/s    93.33%
32     206.45/s    96.40%
64     215.78/s    98.10%
```

Every batch was exact. Batch 64 verified 6,291,456 individual 32-bit residues.

The remaining deterministic cost is serialization of `2B` output words after
each coefficient. This checkpoint adds two coefficient banks so output of
coefficient `k` overlaps input and computation of coefficient `k+1`.

## Architecture

```text
compute bank 0  <---->  output bank 1
compute bank 1  <---->  output bank 0
```

Each bank holds, for up to 64 ciphertexts:

```text
c0
c1
ks_b
ks_a
```

A bank becomes output-ready only after all EvalMul and final-digit BV results
have returned. It is released only after the final ciphertext's `c1` word is
accepted. If output backpressure fills both banks, AXI input stalls safely.

The ten live Barrett pipelines remain unchanged:

```text
6 EvalMul c0/c1 pipelines
4 BV key-switch pipelines
160 DSP48E1 nominal
```

## Apply and simulate

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_pingpong_exact_sim_checkpoint.zip

./run_bv_keyreuse_pingpong_checkpoint.sh
```

Coverage:

```text
6 paired Q-tower profiles
12 BV digits
8 ciphertexts
32 coefficients per tower
3072 exact output words
deterministic output backpressure
explicit simultaneous input/output handshake check
```

Expected ending:

```text
PASS: generated exact coefficient-major evaluation-key-reuse vectors
input_reduction=52.5000%
...
PINGPONG_OVERLAP_HANDSHAKES=...
PASS: exact ping-pong coefficient-major BV evaluation-key reuse across all six tower pairs
BV_KEYREUSE_PINGPONG_SIM_RUN_END

PASS: exact ping-pong coefficient-major evaluation-key-reuse checkpoint complete
```

## Input-bound ceilings

With coefficient output hidden behind the next coefficient's input, the ideal
100 MHz ceilings become:

```text
batch  ideal rate
8      214.16/s
16     232.51/s
32     242.93/s
64     248.49/s
```

The design remains host-decomposed; BV digits are still supplied externally.
