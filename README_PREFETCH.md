# One-product operand-prefetch checkpoint

This checkpoint adds two shadow coefficient stores per tower:

- shadow A: 4 RAMB36
- shadow B: 4 RAMB36

Across two towers the expected additional storage is exactly 16 RAMB36.
There is no result buffer and no extra modular multiplier.

## Important correction

Refill uses the SAME logical address after its result has been captured.
A reverse-address refill would overwrite high result coefficients before
those coefficients were emitted.

## Pipeline

1. Load product 0 directly into the arithmetic stores.
2. Compute product 0 while accepting product 1 into shadow A/B.
3. Emit result address i.
4. After result i has been captured, refill core A[i] and B[i] from the
   shadow stores.
5. Start the next unchanged 631810-cycle arithmetic operation after the
   final refill write drains.
6. While product 1 computes, accept product 2 into the now-free shadow
   stores.

The physical coefficient store already has independent read and write
ports.  The arithmetic core patch changes only idle external-port
arbitration so the A read port remains enabled during a load.  The busy
arithmetic FSM and its cycle count are unchanged.

First regression: four distinct q0/q1 OpenFHE products, randomized input
gaps and output backpressure, three prefetches, and three refills.
