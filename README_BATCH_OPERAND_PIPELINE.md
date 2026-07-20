# Batch AXI operand-write timing isolation

The unpipelined batch wrapper is functionally correct but has only
+0.028 ns standalone synthesis slack. Its worst path begins in the
batch-wrapper FSM and ends at a coefficient-BRAM address input.

This checkpoint registers the A/B write-enable, address, and data
signals at the AXI-to-arithmetic-core boundary.

The pipeline still accepts one operand word per clock. A one-cycle
`STATE_PRODUCT_DRAIN` commits the final B coefficient before asserting
the unchanged arithmetic core's start input.

Expected functional behavior:

- identical MULB protocol
- two exact OpenFHE products in one frame
- one input TLAST
- one output TLAST
- randomized gaps and backpressure still pass
- `core_cycles` remains 214018 with FAST_MODMUL
- physical core target remains 631810 clocks
- wrapper cost is one drain clock per product
- no extra BRAM or DSP
