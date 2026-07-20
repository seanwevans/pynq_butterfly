# Parallel two-tower PYNQ-Z2 checkpoint

This bundle packages the verified two-lane runtime-profile RTL as a
64-bit AXI4-Stream IP, creates a PYNQ-Z2 AXI DMA overlay, and supplies
a board test that loads q0 and q1 profiles concurrently and executes
both OpenFHE RNS tower products in one 1,339,394-cycle arithmetic
interval.

The 64-bit stream packs tower 0 into bits 31:0 and tower 1 into
bits 63:32.
