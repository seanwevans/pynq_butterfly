# Coefficient-major evaluation-key-reuse physical checkpoint

The new transport and datapath are functionally exact:

```text
6 paired Q-tower profiles
12 BV digits
8 ciphertexts
32 coefficients per tower
3072 exact output words
52.5% less input traffic
zero mismatches
```

Before adding ping-pong coefficient banks, this checkpoint measures the actual
resource and timing cost of the first coefficient-major core.

## Architecture under test

```text
8 EvalMul Barrett pipelines
4 BV key-switch Barrett pipelines
64-entry c0 memory
64-entry c1 memory
64-entry ks_b memory
64-entry ks_a memory
fixed-latency launch metadata FIFOs
coefficient-serial output
```

The expected arithmetic population remains:

```text
12 Barrett pipelines * 16 DSP48E1 = 192 DSP48E1
```

## Apply and run

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_coefficient_major_ooc_checkpoint.zip

./build_bv_keyreuse_coefficient_major_ooc.sh
```

Reports and checkpoints are written to:

```text
/mnt/f/v/bv_keyreuse_coefficient_major_ooc
```

Expected ending:

```text
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_ROUTE_WNS_NS=...
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_POST_PHYS_WNS_NS=...
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_BEST_STAGE=...
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_WNS_NS=...
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_FAILING_PATHS=0
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_LUTS=...
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_REGISTERS=...
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_DSP48E1=192
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_RAMB18E1=...
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_RAMB36E1=...
PASS: coefficient-major evaluation-key-reuse core routed at 100 MHz
```

This result determines how much timing and memory margin is available for the
two-bank overlap architecture.
