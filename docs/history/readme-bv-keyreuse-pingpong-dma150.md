# Ping-pong coefficient-major DMA150 overlay

The accumulator pipeline fixed the true critical path. All five standalone
strategies now close at 100 MHz:

```text
ExploreWithRemap:        +0.216 ns
RemapNetDelayHigh:       +0.199 ns
ExplorePostRoutePhysOpt: +0.179 ns
DefaultExplore:          +0.126 ns
ExploreNetDelayHigh:     +0.093 ns
```

Best standalone resources:

```text
LUTs:       6427
registers:  5288
DSP48E1:    160
BRAM:       0
SRLs:       770
```

This checkpoint integrates the fixed ping-pong core into the proven PYNQ-Z2
dual-clock DMA architecture:

```text
core/control:                 100 MHz
DMA/HP0/HP1/SmartConnect:     150 MHz
MM2S async AXIS FIFO depth:   1024
S2MM async AXIS FIFO depth:   1024
DMA width:                    64 bits
DMA length width:             26 bits
DMA burst length:             16
DRE:                          disabled
```

The project implementation run uses the standalone winner:

```text
opt_design:                   ExploreWithRemap
place_design:                 Explore
pre-route phys_opt_design:    Explore
route_design:                 NoTimingRelaxation
post-route phys_opt_design:   Explore
```

## Apply and build

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_pingpong_dma150_overlay_checkpoint.zip

./scripts/vivado/build_bv_keyreuse_pingpong_dma150_overlay.sh
```

Build output:

```text
/mnt/f/v/bv_keyreuse_pingpong_dma150_overlay
```

Deploy output:

```text
deploy/bv_keyreuse_pingpong_dma150/
    evalmul3_bv_keyreuse_pingpong_dma150.bit
    evalmul3_bv_keyreuse_pingpong_dma150.hwh
    build_summary.txt
    routed_timing_summary.rpt
    routed_utilization.rpt
```

The external `RLPF` and `RLCM` protocols are unchanged, so the existing
coefficient-major board runner can be reused after the overlay closes.
