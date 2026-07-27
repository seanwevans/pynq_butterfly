# Exact fused BV-relinearization DMA150 overlay

The connected fused core has now passed both major standalone gates:

```text
Functional:
    exact OpenFHE relinearized c0/c1
    six paired Q-tower profiles
    12 BV digits
    384 checked output words
    zero mismatches

Physical OOC:
    100 MHz
    WNS=+0.016 ns
    failing paths=0
    LUTs=8112
    registers=6775
    DSP48E1=192
```

This checkpoint places that exact fused core behind the proven PYNQ-Z2
dual-clock DMA architecture:

```text
core/control:                 100 MHz
DMA/HP0/HP1/SmartConnect:     150 MHz
MM2S async AXIS FIFO depth:   1024
S2MM async AXIS FIFO depth:   1024
DMA data width:               64 bits
DMA length width:             26 bits
DMA bursts:                   16
DRE:                          disabled
```

The first overlay keeps the current paired-tower `RLPF`/`RLBV` protocol. A
complete 12-tower ciphertext therefore uses six pair transactions. Collapsing
those into one all-pair frame comes after exact board execution.

## Apply and build

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_relinearized_dma150_overlay_checkpoint.zip

./scripts/vivado/build_evalmul3_bv_relinearized_dma150_overlay.sh
```

Build products are written to:

```text
deploy/evalmul3_bv_relinearized_dma150/
    evalmul3_bv_relinearized_dma150.bit
    evalmul3_bv_relinearized_dma150.hwh
    build_summary.txt
    routed_timing_summary.rpt
    routed_utilization.rpt
```

The Vivado implementation strategy is:

```text
Performance_ExplorePostRoutePhysOpt
```

Expected ending:

```text
implementation_strategy=Performance_ExplorePostRoutePhysOpt
impl_status=write_bitstream Complete!
EVALMUL3_BV_RELINEARIZED_DMA150_WNS_NS=...
EVALMUL3_BV_RELINEARIZED_DMA150_FAILING_PATHS=0
EVALMUL3_BV_RELINEARIZED_DMA150_DSP48E1=192
bitstream=...
hardware_handoff=...
PASS: exact fused BV-relinearization dual-clock DMA overlay routed
```

The OOC margin is only `+0.016 ns`, so the full overlay may require a
placement-specific timing adjustment. A clean failure summary remains useful:
it will show whether the limiting path is inside the 100 MHz fused core or in
the 150 MHz DMA subsystem.
