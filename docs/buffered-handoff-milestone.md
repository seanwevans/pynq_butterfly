# Buffered-handoff OpenFHE milestone

## Operation

Exact two-tower OpenFHE `DCRTPoly` multiplication in:

    Z_q[X] / (X^4096 + 1)

Tower parameters:

- q0 = 1073692673
- psi0 = 236231
- q1 = 1073668097
- psi1 = 106172

## Final architecture

- Two RNS towers execute concurrently.
- Two butterflies execute concurrently per polynomial.
- 24 radix-4 modular-multiplier lanes.
- Four-bank arithmetic coefficient stores.
- Runtime-loaded modulus and NTT profiles.
- One prefetched operand pair per tower.
- One buffered result polynomial per tower.
- Four-wide result capture and operand refill.
- 64-bit paired q0/q1 AXI4-Stream.
- Arbitrary batch count.
- Zero DSP usage.

## Physical implementation

- Board: PYNQ-Z2
- Part: XC7Z020-1
- PL clock: 100 MHz
- Implementation: `write_bitstream Complete!`
- WNS: +0.179 ns
- LUT: 31,701
- Registers: 13,956
- RAMB36: 74
- RAMB18: 2
- BRAM tile equivalent: 75
- DSP: 0

Resource composition:

- arithmetic and profile storage: 48 RAMB36
- prefetched operand storage: 16 RAMB36
- buffered result storage: 8 RAMB36
- DMA/interconnect: 2 RAMB36 + 2 RAMB18

## Timing

- Arithmetic core: 631,810 clocks/product
- Four-wide nonfinal handoff: 1,025 clocks
- Steady-state spacing: 632,835 clocks
- Steady-state latency: 6,328.35 us/product

The arithmetic FSM remains unchanged.

## Exact physical validation

Batch counts tested:

    1, 2, 4, 8, 16

Each batch size received one validated first run and 20 timed validated
runs. Across the complete sweep:

- exact DCRTPoly products: 651
- tower results checked: 1,302
- coefficient comparisons: 5,332,992
- mismatches: 0

Batch-16 result:

- minimum batch: 101,706.97 us
- median batch: 101,729.13 us
- mean batch: 101,735.76 us
- p95 batch: 101,769.65 us
- maximum batch: 101,785.71 us
- median per DCRTPoly product: 6,358.07 us
- measured throughput: 157.28 products/s
- OpenFHE CPU reference: 7,161.35 us/product
- end-to-end OpenFHE speedup: 1.126x
- utilization of cycle-derived steady-state limit: 99.53%

## Development progression

Physical median per DCRTPoly product:

- original parallel two-tower overlay: 14,384.08 us
- timing-isolated dual-butterfly overlay: 7,186.59 us
- batch-of-two overlay: 6,865.63 us
- arbitrary batch-16 overlay: 6,515.42 us
- operand-prefetch batch-16 overlay: 6,425.53 us
- buffered-handoff batch-16 overlay: 6,358.07 us

## Next checkpoint

Increase NTT issue width from two to four butterflies per polynomial.

Initial proof order:

1. Eight-bank coefficient-address mapping.
2. Conflict-free four-butterfly schedule for all 12 DIF/DIT stages.
3. Eight-read/eight-write coefficient store.
4. Four-read twiddle infrastructure.
5. Exact q0/q1 cyclic NTT regression.
6. Target 141,313 clocks per transform.
7. Integrate into the unchanged streamed/buffered architecture.

Projected arithmetic target:

- preprocessing: 22,528 clocks
- forward NTT: 141,313 clocks
- pointwise multiplication: 21,504 clocks
- inverse NTT: 141,313 clocks
- postscale: 22,528 clocks
- complete product: 349,186 clocks

Projected buffered steady-state spacing:

    350,211 clocks
    3,502.11 us/product
