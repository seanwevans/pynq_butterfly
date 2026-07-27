# BV key-switch MAC physical checkpoint

The exact RTL checkpoint passed every selected OpenFHE BV coefficient across
all six paired Q-tower profiles under deterministic output backpressure.

The next gate is physical characterization of the standalone production-size
core at `N=4096`.

## Apply

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  bv_keyswitch_mac_ooc_physical_checkpoint.zip
```

## Build

```bash
./scripts/vivado/build_bv_keyswitch_mac_ooc.sh
```

The flow uses:

```text
part:              XC7Z020CLG400-1
top:               bv_keyswitch_mac_two_tower_axis_core
mode:              out_of_context
clock:             100 MHz
clock uncertainty: 0.154 ns
modular pipelines: 4
expected DSP48E1:  64
N:                 4096
MAX_DIGITS:        16
FIFO_DEPTH:        8
```

It performs synthesis, placement, physical optimization, routing, and
post-route physical optimization. Reports and the routed checkpoint are
written to:

```text
/mnt/f/v/bv_keyswitch_mac_ooc
```

A successful ending is:

```text
BV_KEYSWITCH_MAC_OOC_WNS_NS=...
BV_KEYSWITCH_MAC_OOC_FAILING_PATHS=0
BV_KEYSWITCH_MAC_OOC_DSP48E1=64
PASS: standalone exact BV key-switch MAC routed at 100 MHz
```

## Why this precedes fusion

The current EvalMul3 core uses 128 DSP48E1. The BV key-switch MAC should use
64 more, but the PYNQ-Z2 has only 220 total DSP48E1. A fully parallel
128+64=192 DSP design is arithmetically feasible, but placement and clock
routing must be measured before combining the blocks.

This checkpoint establishes:

1. exact standalone timing;
2. actual LUT/register/DSP usage;
3. whether the accumulation and result-FIFO paths close at 100 MHz;
4. the physical margin available for a fused 192-DSP design.

After it closes, the next architecture is a fused stream where EvalMul3 emits
`c0`, `c1`, and `c2`; `c2` feeds the BV MAC; and the final modular additions
produce two relinearized ciphertext components.
