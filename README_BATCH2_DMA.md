# Batch-of-two physical overlay checkpoint

This checkpoint packages the timing-isolated batch AXI wrapper as:

    user.org:user:db2b:1.0

The complete PYNQ-Z2 overlay is built under:

    F:\v\db2b

Deployment output:

    F:\repos\pynq_butterfly\deploy\
        poly_mul4096_dual_butterfly_two_tower_batch_dma

Protocol:

- profile command: `0x50524f46`
- batch command: `0x4d554c42`
- batch count: 2
- profile input: 131072 bytes
- batch input: 131088 bytes
- batch output: 65536 bytes

The arithmetic core remains 631810 clocks per product. The registered
operand-write boundary adds one drain clock per product, so a batch of
two has 1263622 core-plus-drain clocks.
