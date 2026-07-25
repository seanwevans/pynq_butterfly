# Fused relinearization: exact OpenFHE probe

The next accelerator stage is OpenFHE relinearization:

```text
(c0, c1, c2)
        |
KeySwitchCore(c2, eval_key)
        |
(ks_b, ks_a)
        |
(c0 + ks_b, c1 + ks_a)
```

OpenFHE 1.5.1 performs exactly this operation for a three-component product.
The purpose of this checkpoint is to expose every exact intermediate before
choosing the FPGA architecture.

## Why probe both HYBRID and BV

The current EvalMul3 datapath is specialized for 30-bit Q moduli. OpenFHE
supports two relevant key-switch techniques:

- `HYBRID`: fewer large digits, an extended QP basis, and an approximate
  modulus-down stage;
- `BV`: Q-only CRT decomposition and a larger evaluation-key MAC.

HYBRID may introduce special P moduli wider than the current multiplier.
BV avoids P entirely but usually creates more digit/key products. The probe
prints the real dimensions and exports exact vectors for both techniques
rather than guessing.

## Apply after committing the all-pair checkpoint

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  openfhe_fused_relinearization_probe_checkpoint.zip

./begin_evalmul_relinearization_branch.sh
```

## Run

```bash
./run_openfhe_relinearization_probe.sh
```

The script builds the existing OpenFHE bridge plus a new executable and runs:

```text
HYBRID, 12 Q towers, 3 large digits
BV,     12 Q towers, digitSize=0
```

For each technique it proves:

```text
KeySwitchCore(c2)
    ==
EvalFastKeySwitchCore(
    EvalKeySwitchPrecomputeCore(c2),
    eval_key
)

c0 + keyswitch[0]
    ==
OpenFHE EvalMult output c0

c1 + keyswitch[1]
    ==
OpenFHE EvalMult output c1
```

## Exported vectors

Each output directory contains:

```text
metadata.json
profiles_q/
profiles_p/                 HYBRID only
c2_q_eval/
digits/digitNNN/
eval_key_a/digitNNN/
eval_key_b/digitNNN/
keyswitch_q_a/
keyswitch_q_b/
keyswitch_ext_a/            HYBRID only
keyswitch_ext_b/            HYBRID only
relinearized_c0_q/
relinearized_c1_q/
```

Polynomial tower files are unsigned 64-bit little-endian words so the probe
can faithfully represent both 30-bit Q values and any wider P values.

## Decision gate

The output fields that matter most are:

```text
technique
q_towers
p_towers
digits
digit_towers
eval_key_parts
eval_key_towers
max_q_modulus_bits
max_p_modulus_bits
digit_bytes
eval_key_bytes
precompute_us
extended_mac_us
direct_keyswitch_us
```

The first FPGA relinearization checkpoint will accelerate the evaluation-key
multiply-accumulate stage using these exported exact digits and keys. The
decomposition and HYBRID modulus-down stages remain separate until the probe
shows which technique maps cleanly onto the XC7Z020.
