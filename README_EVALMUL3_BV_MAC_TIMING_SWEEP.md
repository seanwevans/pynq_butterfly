# 192-DSP timing-recovery sweep

The first combined implementation was very close:

```text
WNS=-0.086 ns
failing paths=48
DSP48E1=192
```

This is a placement/routing miss of 0.86% of the 10 ns clock period, not a
capacity failure.

The patch removes `DONT_TOUCH` from the two top-level engine instances while
retaining `KEEP_HIERARCHY`, then synthesizes once and tries three Vivado
implementation combinations:

```text
ExplorePostRoutePhysOpt
ExploreWithRemap
NetDelayHigh
```

For each strategy it measures the routed design both before and after
post-route physical optimization and preserves the best checkpoint.

Apply and run:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o   evalmul3_bv_mac_timing_recovery_sweep.zip

./build_evalmul3_bv_mac_timing_sweep.sh
```

Results are written to:

```text
/mnt/f/v/evalmul3_bv_mac_timing_sweep
```
