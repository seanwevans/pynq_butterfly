# Ping-pong coefficient-major OOC physical checkpoint

The two-bank scheduler is functionally exact:

```text
6 paired Q-tower profiles
12 BV digits
8 ciphertexts
32 coefficients per tower
3072 exact output words
1552 simultaneous input/output handshakes
zero mismatches
```

This checkpoint measures the physical cost of duplicating the coefficient
state and adding independent input/output schedulers.

## Architecture under test

```text
10 live Barrett pipelines
160 DSP48E1 nominal

bank 0:
    c0[64], c1[64], ks_b[64], ks_a[64]

bank 1:
    c0[64], c1[64], ks_b[64], ks_a[64]

independent ordered output scheduler
safe two-bank backpressure stall
```

## Apply and run

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_pingpong_ooc_checkpoint.zip

./build_bv_keyreuse_pingpong_ooc.sh
```

Reports and checkpoints are written to:

```text
/mnt/f/v/bv_keyreuse_pingpong_ooc
```

The implementation uses the previously winning strategy:

```text
opt_design:                 Default
place_design:               ExtraNetDelay_high
pre-route phys_opt_design:  AggressiveExplore
route_design:               NoTimingRelaxation
post-route phys_opt_design: AggressiveExplore
```

Expected ending:

```text
BV_KEYREUSE_PINGPONG_OOC_SYNTH_DSP48E1=160
BV_KEYREUSE_PINGPONG_OOC_ROUTE_WNS_NS=...
BV_KEYREUSE_PINGPONG_OOC_POST_PHYS_WNS_NS=...
BV_KEYREUSE_PINGPONG_OOC_BEST_STAGE=...
BV_KEYREUSE_PINGPONG_OOC_WNS_NS=...
BV_KEYREUSE_PINGPONG_OOC_FAILING_PATHS=0
BV_KEYREUSE_PINGPONG_OOC_LUTS=...
BV_KEYREUSE_PINGPONG_OOC_REGISTERS=...
BV_KEYREUSE_PINGPONG_OOC_DSP48E1=160
BV_KEYREUSE_PINGPONG_OOC_RAMB18E1=...
BV_KEYREUSE_PINGPONG_OOC_RAMB36E1=...
BV_KEYREUSE_PINGPONG_OOC_SRL=...
PASS: ping-pong coefficient-major evaluation-key-reuse core routed at 100 MHz
```

The result determines whether the ping-pong core can move directly into the
dual-clock DMA overlay or first needs memory-placement or timing cleanup.
