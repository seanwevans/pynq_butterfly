# Coefficient-major BV evaluation-key reuse

The exact board checkpoint achieved:

```text
94.90 relinearized EvalMult/s data path
91.37/s profile-inclusive
93.29% of its protocol ceiling
```

The bottleneck was retransmitting 24 evaluation-key words for every
ciphertext and coefficient.

This checkpoint implements the first coefficient-major transport and datapath.

## New frame order

For a batch of eight ciphertexts and twelve BV digits, each coefficient sends:

```text
for each of 8 ciphertexts:
    a0, a1, b0, b1                 32 words

for each of 12 digits:
    eval_key_b, eval_key_a          24 words total
    8 ciphertext digit words        96 words
                                    --------
                                    152 words
```

The old frame used:

```text
8 * 40 = 320 words/coefficient
```

This is a **52.5% input reduction**.

The evaluation key is held in registers while eight digit words launch through
the four BV Barrett pipelines. The core retains all eight EvalMul pipelines,
including the c2 products, for a total of twelve Barrett pipelines and the same
nominal 192 DSP48E1 arithmetic population.

## Apply and simulate

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_coefficient_major_sim_checkpoint.zip

./run_bv_keyreuse_coefficient_major_checkpoint.sh
```

The existing `relin_bv_t12_d0` vectors are reused. The converter replicates the
same exact OpenFHE ciphertext eight times, changes only the wire order, and
expects eight copies of the exact OpenFHE relinearized result.

Coverage:

```text
6 paired Q-tower profiles
12 BV digits
8 ciphertexts
32 coefficients per tower
3072 final output words
deterministic output backpressure
```

Expected ending:

```text
PASS: generated exact coefficient-major evaluation-key-reuse vectors
input_reduction=52.5000%
...
PASS: exact coefficient-major BV evaluation-key reuse across all six tower pairs
BV_KEYREUSE_COEFFICIENT_MAJOR_SIM_RUN_END

PASS: exact coefficient-major evaluation-key-reuse RTL checkpoint complete
```

## First-checkpoint throughput boundary

This version intentionally drains the completed coefficient's `2B` output
words before accepting the next coefficient. Its no-backpressure core schedule
at batch eight is approximately:

```text
152 input cycles
  8 multiplier drain cycles
 16 output cycles
-----------------
176 cycles/coefficient
```

Across six tower pairs, that is roughly:

```text
540672 cycles/ciphertext
5406.72 us/ciphertext
184.96 ciphertexts/s ideal
```

That is already about 1.82 times the current protocol ceiling. The next patch
will ping-pong two coefficient banks so output overlaps input, moving the ideal
toward the previously calculated 214.16/s at batch eight and 248.49/s at batch
64.

BV decomposition remains host-side.
