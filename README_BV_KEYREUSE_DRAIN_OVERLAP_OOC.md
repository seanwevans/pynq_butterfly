# Compute-drain-overlap OOC timing sweep

Exact simulation passed:

```text
3072 exact output words
1581 simultaneous input/output handshakes
930 next-coefficient-input/prior-bank-drain overlap handshakes
0 mismatches
```

This checkpoint measures the physical cost of:

```text
bank-tagged Eval metadata
bank-tagged BV metadata
bank-tagged accumulator pipeline
per-bank Eval completion counters
per-bank final-digit BV commit counters
occupied/ready/free ownership tracking
immediate alternate-bank input launch
```

The ten Barrett pipelines remain unchanged:

```text
160 DSP48E1 nominal
```

## Apply and run

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_drain_overlap_ooc_timing_sweep.zip

./build_bv_keyreuse_drain_overlap_ooc_timing_sweep.sh
```

Output:

```text
/mnt/f/v/bv_keyreuse_drain_overlap_ooc_timing_sweep
```

Five strategies reuse the same post-synthesis checkpoint:

```text
ExploreWithRemap
RemapNetDelayHigh
DefaultExplore
ExplorePostRoutePhysOpt
ExploreNetDelayHigh
```

Expected ending:

```text
BV_KEYREUSE_DRAIN_OVERLAP_OOC_SYNTH_DSP48E1=160
STRATEGY_..._ROUTE_WNS_NS=...
STRATEGY_..._POST_PHYS_WNS_NS=...
BV_KEYREUSE_DRAIN_OVERLAP_OOC_BEST_STRATEGY=...
BV_KEYREUSE_DRAIN_OVERLAP_OOC_BEST_STAGE=...
BV_KEYREUSE_DRAIN_OVERLAP_OOC_WNS_NS=...
BV_KEYREUSE_DRAIN_OVERLAP_OOC_FAILING_PATHS=0
BV_KEYREUSE_DRAIN_OVERLAP_OOC_DSP48E1=160
PASS: coefficient-major compute-drain-overlap core routed at 100 MHz
```

The best checkpoint is copied to:

```text
/mnt/f/v/bv_keyreuse_drain_overlap_ooc_timing_sweep/best_routed.dcp
```
