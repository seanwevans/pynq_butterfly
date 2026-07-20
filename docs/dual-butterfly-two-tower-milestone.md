# Dual-butterfly two-tower OpenFHE milestone

## Architecture

- Ring: `Z_q[X]/(X^4096 + 1)`
- OpenFHE towers:
  - `q0 = 1073692673`
  - `q1 = 1073668097`
- Two RNS towers execute concurrently.
- Two butterflies execute concurrently within each tower.
- Four-bank coefficient stores support four coefficient accesses per cycle.
- Runtime profile tables use true-dual-port XPM block RAM.
- Butterfly inputs are registered to isolate coefficient BRAM outputs from the modular multipliers.
- Total modular-multiplier lanes: 24
- DSP usage: 0

## Core result

- Previous parallel core: 1,339,394 cycles
- Dual-butterfly timing-isolated core: 631,810 cycles
- Core speedup: 2.1199x
- Core latency at 100 MHz: 6,318.10 us
- Modular multiplications per two-tower product: 180,224

## Physical implementation

- Device: PYNQ-Z2 / XC7Z020
- Clock: 100 MHz
- Implementation status: `write_bitstream Complete!`
- WNS: +0.017 ns
- LUT: 28,513
- Registers: 13,268
- DSP: 0
- RAMB36: 50
- RAMB18: 2
- Accelerator BRAM: 48 RAMB36
- Complete-overlay BRAM equivalent: 51 tiles

## Physical OpenFHE validation

All FPGA coefficients matched the corresponding OpenFHE two-tower
`DCRTPoly` product.

- First product: 7,480.32 us
- Timed products: 20/20 exact
- Minimum: 7,147.69 us
- Median: 7,186.59 us
- Mean: 7,208.02 us
- p95: 7,239.22 us
- Maximum: 7,603.36 us
- DCRTPoly products/s: 139.15
- Individual tower products/s: 278.30
- Arithmetic ceiling: 158.28 DCRTPoly products/s
- Median DMA/software overhead: 868.49 us

The previous physical overlay had a 14,384.08 us median. The new
overlay is 2.002x faster.

The measured OpenFHE CPU reference was 7,161.35 us. The FPGA median is
25.24 us, or approximately 0.35%, slower. The fastest FPGA run is
13.66 us faster than the CPU reference.

## Next checkpoint

Implement batched or resident execution so several products share one
DMA transaction. Removing approximately 25.24 us, or 2.91% of the
current DMA/software overhead, moves the median FPGA result below the
measured OpenFHE CPU reference.
