# 160-DSP coefficient-major timing-recovery sweep

The first physical implementation is close:

```text
route WNS:       -0.213 ns
post-phys WNS:   -0.121 ns
failing paths:   20
LUTs:            6184
registers:       4937
DSP48E1:         160
BRAM:            0
SRLs:            770
```

A 121 ps miss is small enough to try implementation strategy recovery before
changing exact RTL.

This checkpoint synthesizes once and implements the same post-synthesis DCP
three ways:

```text
ExplorePostRoutePhysOpt
ExploreWithRemap
NetDelayHigh
```

These are the strategy families that recovered the earlier 192-DSP
co-residency design.

## Apply and run

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_160dsp_timing_sweep.zip

./scripts/vivado/build_bv_keyreuse_160dsp_timing_sweep.sh
```

Output:

```text
/mnt/f/v/bv_keyreuse_160dsp_timing_sweep
```

Each strategy gets route and post-route-phys timing reports. The best routed
checkpoint is copied to:

```text
/mnt/f/v/bv_keyreuse_160dsp_timing_sweep/best_routed.dcp
```

Expected ending:

```text
STRATEGY_..._ROUTE_WNS_NS=...
STRATEGY_..._POST_PHYS_WNS_NS=...
BV_KEYREUSE_160DSP_TIMING_SWEEP_BEST_STRATEGY=...
BV_KEYREUSE_160DSP_TIMING_SWEEP_BEST_STAGE=...
BV_KEYREUSE_160DSP_TIMING_SWEEP_WNS_NS=...
BV_KEYREUSE_160DSP_TIMING_SWEEP_FAILING_PATHS=0
BV_KEYREUSE_160DSP_TIMING_SWEEP_DSP48E1=160
PASS: 160-DSP coefficient-major evaluation-key-reuse core routed at 100 MHz
```

No arithmetic or protocol change is made. If all three strategies remain
negative, the generated `best_critical_paths.rpt` will identify the exact RTL
path to pipeline.
