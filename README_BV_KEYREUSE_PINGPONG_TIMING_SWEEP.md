# Ping-pong timing-recovery sweep

The first ping-pong physical result is close but not closed:

```text
route WNS:       -0.443 ns
post-phys WNS:   -0.160 ns
failing paths:   31
LUTs:            6820
registers:       5023
DSP48E1:         160
BRAM:            0
SRLs:            770
```

The second coefficient bank adds only 636 LUTs over the serialized core, but
the new bank-selection/output paths cost 229 ps relative to the serialized
core's `+0.069 ns`.

Before changing exact RTL, this checkpoint synthesizes once and tries five
combinations of directives that have already run successfully in this project:

```text
ExploreWithRemap
RemapNetDelayHigh
ExploreNetDelayHigh
DefaultExplore
ExplorePostRoutePhysOpt
```

## Apply and run

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_pingpong_timing_sweep.zip

./scripts/vivado/build_bv_keyreuse_pingpong_timing_sweep.sh
```

Output:

```text
/mnt/f/v/bv_keyreuse_pingpong_timing_sweep
```

Every strategy gets route and post-route-phys timing reports. The best result
is copied to:

```text
/mnt/f/v/bv_keyreuse_pingpong_timing_sweep/best_routed.dcp
```

Expected summary:

```text
STRATEGY_..._ROUTE_WNS_NS=...
STRATEGY_..._POST_PHYS_WNS_NS=...
BV_KEYREUSE_PINGPONG_TIMING_SWEEP_BEST_STRATEGY=...
BV_KEYREUSE_PINGPONG_TIMING_SWEEP_BEST_STAGE=...
BV_KEYREUSE_PINGPONG_TIMING_SWEEP_WNS_NS=...
BV_KEYREUSE_PINGPONG_TIMING_SWEEP_FAILING_PATHS=...
BV_KEYREUSE_PINGPONG_TIMING_SWEEP_DSP48E1=160
```

A nonnegative result records:

```text
PASS: ping-pong coefficient-major evaluation-key-reuse core routed at 100 MHz
```

If every strategy remains negative, `best_critical_paths.rpt` contains the
100 worst paths and the next patch will pipeline the actual bank-selection or
output-adder path rather than guessing.
