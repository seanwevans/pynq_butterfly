# Four-butterfly two-tower PYNQ-Z2 milestone

## Arithmetic core

- Exact OpenFHE multiplication in both q0 and q1 RNS towers
- N = 4096 negacyclic polynomial multiplication
- Four pipelined butterflies per tower
- 22,968 clocks per two-tower product
- 229.68 us arithmetic latency at 100 MHz
- 90,112 modular multiplications per tower

## Physical two-tower core

- LUT: 24,458
- Registers: 11,004
- CARRY4: 1,382
- DSP48E1: 128
- RAMB18E1: 32
- RAMB36E1: 64
- WNS: +0.081 ns
- Winning strategy: Performance_ExploreWithRemap

## Direct DMA result

- Exact q0/q1 OpenFHE result
- Median: 1,144.10 us/product
- Throughput: 874.05 two-tower products/s

## Batched DMA result

Batch-32 measurement:

- Exact q0/q1 OpenFHE results
- Median: 13,820.30 us/batch
- 431.88 us/product
- 2,315.43 two-tower products/s
- 91.1% of the direct-stream hardware limit
- 14.72x faster than the previous 157.28 products/s overlay

All tested MUL1 and MULB results matched OpenFHE.
