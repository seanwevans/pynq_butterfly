# Four-wide buffered handoff checkpoint

This checkpoint adds one four-bank result store per tower and adds a handoff-capable copy of the proven arithmetic core with an
idle-only four-wide read/write port on its existing coefficient stores. The
original core module and prior overlays remain untouched.

For each completed product, 1024 four-coefficient groups are processed:

- core result A -> result buffer
- shadow A -> core A
- shadow B -> core B

The next arithmetic product starts on the final handoff write edge.  The
previous result then streams from the result buffer while the next product
computes and the following operands prefetch into the shadow stores.

Expected storage:

- existing two-tower prefetch design: 64 RAMB36
- one result buffer per tower: +8 RAMB36
- standalone total: 72 RAMB36

The arithmetic FSM and its 631810-cycle schedule are unchanged.  The expected
handoff is 1025 clocks, yielding a 632835-clock steady-state product spacing.
