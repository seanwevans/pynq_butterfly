# Exact fused relinearization physical checkpoint

The complete host-decomposed BV relinearization RTL is now exact against
OpenFHE across all six paired tower profiles:

```text
12 BV digits
32 coefficients per tower
384 exact final output words
deterministic output backpressure
zero mismatches
```

This build physically implements the connected production-size core:

```text
EvalMul3 arithmetic:       128 DSP48E1
BV evaluation-key MAC:     64 DSP48E1
final modular additions:    0 DSP48E1
alignment/control:           0 DSP48E1
                          -------------
expected total:            192 DSP48E1
```

## Apply and run

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_relinearized_ooc_physical_checkpoint.zip

./build_evalmul3_bv_relinearized_ooc.sh
```

Reports and checkpoints are written to:

```text
/mnt/f/v/evalmul3_bv_relinearized_ooc
```

The flow uses the strategy that closed the 192-DSP co-residency test:

```text
opt_design        Explore
place_design      Explore
phys_opt_design   Explore
route_design      Explore
post-route phys   Explore
```

It records routed timing before and after post-route physical optimization and
keeps the better checkpoint.

Expected ending:

```text
EVALMUL3_BV_RELINEARIZED_OOC_ROUTE_WNS_NS=...
EVALMUL3_BV_RELINEARIZED_OOC_POST_PHYS_WNS_NS=...
EVALMUL3_BV_RELINEARIZED_OOC_BEST_STAGE=...
EVALMUL3_BV_RELINEARIZED_OOC_WNS_NS=...
EVALMUL3_BV_RELINEARIZED_OOC_FAILING_PATHS=0
EVALMUL3_BV_RELINEARIZED_OOC_DSP48E1=192
PASS: exact fused EvalMul3 plus BV relinearization routed at 100 MHz
```

This is the final standalone physical gate before placing the fused core behind
the dual-clock DMA overlay.
