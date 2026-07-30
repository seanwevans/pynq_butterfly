# Next architecture: coefficient-major evaluation-key reuse

The board checkpoint is exact, but transport-bound.

For every coefficient of every ciphertext, the current `RLBV` frame sends:

```text
4 EvalMul operands
12 decomposition digits
24 evaluation-key words
-----------------------
40 input words
```

The 24 evaluation-key words are identical for every ciphertext. Sending them
again for every ciphertext fixes the large-batch ceiling at:

```text
101.725 relinearized EvalMult/s
```

## Coefficient-major batch order

Process one coefficient across a ciphertext batch:

```text
for each coefficient:
    for each ciphertext:
        a0, a1, b0, b1

    for each BV digit:
        eval_key_b
        eval_key_a

        for each ciphertext:
            digit
```

For a batch of `B`, input words per coefficient become:

```text
4B + 12(B + 2)
= 16B + 24
```

Per ciphertext:

```text
16 + 24/B words
```

Ideal 100 MHz ceilings across six tower pairs:

```text
B=8:   214.16 ciphertexts/s
B=32:  242.93 ciphertexts/s
B=64:  248.49 ciphertexts/s
B->∞:  254.31 ciphertexts/s
```

Only one coefficient is live. At batch 64, storing `c0`, `c1`, `ks_b`, and
`ks_a` for every ciphertext requires 2 KiB.

## Important boundary

This remains host-decomposed. BV digits depend on `c2`.

A production OpenFHE API path must eventually either:

1. return `c2`, decompose on the host, and perform key switching in a second
   FPGA pass; or
2. implement BV CRT decomposition on the FPGA.

The current result proves the dense modular arithmetic and full physical
overlay, but does not remove host-generated digits.
