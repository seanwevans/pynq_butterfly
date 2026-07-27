# EvalMul3 + BV-MAC 192-DSP co-residency checkpoint

The standalone BV key-switch MAC closed at 100 MHz:

```text
WNS=+0.430 ns
failing paths=0
LUTs=2662
registers=2445
DSP48E1=64
BRAM=0
```

The next gate is whether it can physically coexist with the exact
`EvalMultNoRelin` engine on the XC7Z020.

This checkpoint instantiates both proven engines under one clock while keeping
their AXI4-Stream interfaces independent:

```text
EvalMul3 engine: 8 Barrett pipelines = 128 DSP48E1
BV-MAC engine:   4 Barrett pipelines =  64 DSP48E1
                                      ---------------
combined arithmetic population       = 192 DSP48E1
```

No arithmetic is duplicated for test purposes, and `DONT_TOUCH` preserves both
hierarchies.

## Apply and build

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_mac_192dsp_coresidency_checkpoint.zip

./scripts/vivado/build_evalmul3_bv_mac_coresidency_ooc.sh
```

Reports are written to:

```text
/mnt/f/v/evalmul3_bv_mac_coresidency
```

A successful ending is:

```text
EVALMUL3_BV_MAC_CORESIDENCY_WNS_NS=...
EVALMUL3_BV_MAC_CORESIDENCY_FAILING_PATHS=0
EVALMUL3_BV_MAC_CORESIDENCY_DSP48E1=192
EVALMUL3_BV_MAC_CORESIDENCY_EVALMUL_DSP48E1=128
EVALMUL3_BV_MAC_CORESIDENCY_BV_DSP48E1=64
PASS: exact EvalMul3 and BV-MAC arithmetic cores co-routed at 100 MHz
```

## What comes after this build

Once 192-DSP co-residency closes, the functional fusion checkpoint will add:

```text
one shared q/mu profile
one external fused frame
c0/c1 alignment FIFO
BV-MAC output alignment
final modular additions:
    relin_c0 = c0 + ks_b mod q
    relin_c1 = c1 + ks_a mod q
two-component output frame
```

BV CRT decomposition remains on the host for that checkpoint. Moving
decomposition onto the FPGA is a separate NTT/basis-conversion stage and
should not be mixed into the first exact fused datapath.
