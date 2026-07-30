# All-pair post-route timing recovery

The first all-pair implementation missed timing for two unrelated reasons:

```text
clk_fpga_1 / DMA S2MM:  -0.155 ns
clk_fpga_0 / Barrett:   -0.026 ns
```

The worst path is entirely inside the AXI DMA S2MM data mover. The repeated
core failures are the already known Barrett DSP chain. No new EVPT/EV12
sequencer or payload-FIFO path appears among the reported critical paths.

The previous implementation strategy was:

```text
Performance_ExploreWithRemap
```

This patch changes only the implementation strategy to:

```text
Performance_ExplorePostRoutePhysOpt
```

That strategy retains timing-driven exploration and adds physical
optimization after routing. This is the correct first recovery attempt for a
155 ps routed miss with 43% route delay.

It also replaces the misleading failure text `missed 100 MHz` with a generic
routed-timing failure and records the actual worst path group.

## Apply and rebuild

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_allpairs_postroute_timing_fix.zip

./scripts/vivado/build_evalmul3_allpairs_dma150_overlay.sh
```

The build directory is recreated by the launcher, so no manual deletion is
required.

## Decision after the run

A successful run ends with:

```text
PASS: all-pair evaluation-domain dual-clock DMA overlay routed
```

If the DMA path still fails while the 100 MHz core closes, the next fallback
is to change FCLK1 to the next slower realizable Zynq divider while leaving
the arithmetic core at 100 MHz. Do not lower the core clock.
