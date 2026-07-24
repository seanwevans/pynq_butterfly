# Batch-of-two AXI checkpoint

This checkpoint adds a generic `MULB` command to the AXI wrapper while
leaving the 631810-cycle arithmetic core unchanged.

## Batch protocol

Each 64-bit stream word contains:

- bits 31:0: q0 tower word
- bits 63:32: q1 tower word

Input frame for batch count `B`:

1. `0x4d554c42` (`MULB`)
2. positive batch count `B`
3. for every product: 4096 A words followed by 4096 B words

`TLAST` is asserted only on the final B coefficient of the final
product.

Output is `B` consecutive 4096-word products. `TLAST` is asserted only
on the final coefficient of the final product.

The wrapper deliberately uses no additional coefficient storage. It
stalls the input DMA while the unchanged arithmetic core computes and
while the corresponding result is returned.

The regression generates two distinct products through the existing
OpenFHE bridge, then starts the input sender and output receiver
concurrently. This models the independent MM2S and S2MM DMA channels and
prevents the expected mid-frame backpressure from deadlocking the test.
