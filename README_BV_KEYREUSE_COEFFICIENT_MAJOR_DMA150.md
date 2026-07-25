# Coefficient-major evaluation-key-reuse DMA150 overlay

The exact coefficient-major core now closes standalone:

```text
best strategy:   NetDelayHigh
best stage:      route
WNS:             +0.069 ns
failing paths:   0
LUTs:            6184
registers:       5031
DSP48E1:         160
BRAM:            0
SRLs:            770
```

This checkpoint places that core behind the proven PYNQ-Z2 dual-clock DMA
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

The project implementation run uses the same directives that produced the
standalone `+0.069 ns` result:

```text
opt_design:                   Default
place_design:                 ExtraNetDelay_high
pre-route phys_opt_design:    AggressiveExplore
route_design:                 NoTimingRelaxation
post-route phys_opt_design:   AggressiveExplore
```

## Apply and build

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_coefficient_major_dma150_overlay_checkpoint.zip

./build_bv_keyreuse_coefficient_major_dma150_overlay.sh
```

Build output:

```text
/mnt/f/v/bv_keyreuse_coefficient_major_dma150_overlay
```

Deploy output:

```text
deploy/bv_keyreuse_coefficient_major_dma150/
    evalmul3_bv_keyreuse_coefficient_major_dma150.bit
    evalmul3_bv_keyreuse_coefficient_major_dma150.hwh
    build_summary.txt
    routed_timing_summary.rpt
    routed_utilization.rpt
```

Expected ending:

```text
implementation_strategy=NetDelayHigh
opt_directive=Default
place_directive=ExtraNetDelay_high
pre_route_phys_opt_directive=AggressiveExplore
route_directive=NoTimingRelaxation
post_route_phys_opt_directive=AggressiveExplore
impl_status=write_bitstream Complete!
BV_KEYREUSE_COEFFICIENT_MAJOR_DMA150_WNS_NS=...
BV_KEYREUSE_COEFFICIENT_MAJOR_DMA150_FAILING_PATHS=0
BV_KEYREUSE_COEFFICIENT_MAJOR_DMA150_DSP48E1=160
bitstream=...
hardware_handoff=...
PASS: coefficient-major evaluation-key-reuse dual-clock DMA overlay routed
```

For `B=64`, the coefficient-major input frame is approximately 32.75 MiB per
pair, safely below the 26-bit DMA length limit. The board runner comes after
this physical overlay closes.
