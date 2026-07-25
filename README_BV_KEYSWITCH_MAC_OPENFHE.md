# Exact OpenFHE BV key-switch MAC checkpoint

The relinearization probe makes the first hardware choice decisive: use BV,
not HYBRID, for the first FPGA implementation.

The HYBRID MAC itself is small, but the real operation requires two 60-bit P
towers, basis extension, and approximate modulus-down. BV stays entirely in
the proven 12-tower, 30-bit Q basis.

This checkpoint computes the exact dense arithmetic at the center of BV
relinearization:

```text
ks_b = sum_j digit_j * eval_key_b_j mod q
ks_a = sum_j digit_j * eval_key_a_j mod q
```

It uses four existing Barrett pipelines:

```text
2 packed towers
x 2 evaluation-key components
= 4 modular multipliers
```

That should synthesize to approximately 64 DSP48E1, leaving half of the
current EvalMul3 multiplier budget available for later fusion.

## Apply

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  bv_keyswitch_mac_openfhe_checkpoint.zip
```

## Run

The exact BV probe vectors must already exist at:

```text
openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0
```

Then run:

```bash
./run_bv_keyswitch_mac_checkpoint.sh
```

The flow:

1. reads the real OpenFHE BV digits and A/B evaluation keys;
2. independently recomputes every selected modular MAC in Python;
3. verifies the Python results against exported `KeySwitchCore` outputs;
4. creates paired-tower `BVPF` and `BVKM` vectors;
5. simulates all six Q-tower pairs;
6. checks exact `ks_b` and `ks_a` outputs under deterministic backpressure.

The first checkpoint uses the leading 32 evaluation-domain coefficients from
all six tower pairs. Each coefficient is independent in evaluation form, so
this tests the production arithmetic and framing without making Icarus process
the entire 4096-coefficient vector set.

Expected ending:

```text
PASS: exact BV digit/key products reproduce OpenFHE KeySwitchCore contributions
...
PASS: exact OpenFHE BV key-switch MAC across all six tower pairs
BV_KEYSWITCH_MAC_SIM_RUN_END

PASS: exact OpenFHE BV key-switch MAC RTL checkpoint complete
```

## Wire protocol

### `BVPF`

```text
word 0: duplicated 0x42565046
word 1: {q1, q0}
word 2: {mu1, mu0}, TLAST
```

### `BVKM`

```text
word 0: duplicated 0x42564B4D
word 1: {digit_count, ciphertext_count}

for each ciphertext, coefficient, and digit:
    digit
    eval_key_b
    eval_key_a

output for each coefficient:
    ks_b
    ks_a
```

The final input `eval_key_a` and final output `ks_a` carry `TLAST`.

## Architectural consequence

The naive stream consumes three 64-bit words per digit, or 36 input clocks per
coefficient for the observed 12-digit BV configuration. The arithmetic core
can therefore launch one digit every three clocks and remains transport-bound.

The later fused design should reuse evaluation keys across a ciphertext batch
rather than resend the 9 MiB key for every ciphertext. First we establish exact
RTL behavior and physical cost.
