# RTL architecture

The current design separates the 100 MHz arithmetic domain from the 150 MHz
DMA domain. The coefficient-major core has two coefficient banks: one drains
completed products while the other accepts the next coefficient. Independent
completion counters cover both EvalMult products and BV accumulator writes.

A register boundary separates BV metadata/accumulator reads from modular-add
and accumulator writes. This keeps the ten-multiplier core at 160 DSP48E1s while
allowing compute, drain, and transport to overlap. Start at
[`session-protocol.md`](session-protocol.md) for the top-level behavior and use
the [history index](../README.md#historical-lineage) for implementation fixes.
