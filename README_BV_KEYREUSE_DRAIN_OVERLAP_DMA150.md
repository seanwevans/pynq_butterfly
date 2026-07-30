# Compute-drain-overlap DMA150 overlay

The exact drain-overlap core closes standalone:

```text
best strategy:  ExploreWithRemap
best stage:     route
WNS:            +0.317 ns
failing paths:  0
LUTs:           6459
registers:      5432
DSP48E1:        160
BRAM:           0
SRLs:           770
```

This checkpoint integrates that core into the proven PYNQ-Z2 dual-clock DMA
architecture:

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

The implementation uses the OOC winner:

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
  evalmul3_bv_keyreuse_drain_overlap_dma150_overlay_checkpoint.zip

./scripts/vivado/build_bv_keyreuse_drain_overlap_dma150_overlay.sh
```

Build output:

```text
/mnt/f/v/bv_keyreuse_drain_overlap_dma150_overlay
```

Deploy output:

```text
deploy/bv_keyreuse_drain_overlap_dma150/
    evalmul3_bv_keyreuse_drain_overlap_dma150.bit
    evalmul3_bv_keyreuse_drain_overlap_dma150.hwh
    build_summary.txt
    routed_timing_summary.rpt
    routed_utilization.rpt
```

Expected ending:

```text
implementation_strategy=ExploreWithRemap
impl_status=write_bitstream Complete!
BV_KEYREUSE_DRAIN_OVERLAP_DMA150_WNS_NS=...
BV_KEYREUSE_DRAIN_OVERLAP_DMA150_FAILING_PATHS=0
BV_KEYREUSE_DRAIN_OVERLAP_DMA150_DSP48E1=160
bitstream=...
hardware_handoff=...
PASS: coefficient-major compute-drain-overlap dual-clock DMA overlay routed
```

The external `RLPF` and `RLCM` protocols remain unchanged.
