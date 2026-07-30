# OpenFHE relinearization probe result

The exact OpenFHE 1.5.1 probe completed for both key-switch techniques.

## HYBRID

```text
q_towers=12
p_towers=2
digits=3
digit_towers=14
eval_key_parts=3
eval_key_towers=14
max_q_modulus_bits=30
max_p_modulus_bits=60
digit_bytes=1376256
eval_key_bytes=2752512
precompute_us=33161.85
fast_keyswitch_us=3744.18
direct_keyswitch_us=43194.07
extended_mac_us=725.61
```

HYBRID has a small evaluation-key MAC, but requires two 60-bit special-prime
towers plus basis extension and approximate modulus-down. The current modular
multiplier is specialized for 30-bit moduli, and the measured precompute stage
dominates the operation.

## BV with digitSize=0

```text
q_towers=12
p_towers=0
digits=12
digit_towers=12
eval_key_parts=12
eval_key_towers=12
max_q_modulus_bits=30
max_p_modulus_bits=0
digit_bytes=4718592
eval_key_bytes=9437184
precompute_us=6377.11
fast_keyswitch_us=2392.90
direct_keyswitch_us=6280.48
```

BV remains entirely in the existing 12-tower, 30-bit Q basis. Its exact
coefficient-wise MAC is:

```text
ks_b[i,k] = sum_j digit[j,i,k] * eval_key_b[j,i,k] mod q_i
ks_a[i,k] = sum_j digit[j,i,k] * eval_key_a[j,i,k] mod q_i
```

## Decision

The first FPGA relinearization line will use BV.

This is not a claim that BV is universally superior to HYBRID. It is the
correct first architecture for this XC7Z020 design because:

1. every modulus fits the proven 30-bit Barrett datapath;
2. there is no P basis;
3. there is no approximate modulus-down stage;
4. the arithmetic is a direct evaluation-domain modular MAC;
5. the existing two-tower lane packing applies unchanged.

The immediate checkpoint accelerates only the evaluation-key MAC using exact
OpenFHE-exported digits and keys. CRT decomposition remains in software until
the MAC datapath is exact and physically characterized.
