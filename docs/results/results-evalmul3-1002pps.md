# PYNQ-Z2 fused OpenFHE EvalMultNoRelin: 1K milestone

## Exact encrypted workload

```text
ring dimension                 4096
RNS towers                     12
tower pairs                    6
ciphertexts                    384
input ciphertext components    2
output ciphertext components   3
verified tower-components      13,824
```

Every FPGA output matched OpenFHE exactly:

```text
c0 = a0*b0
c1 = a0*b1 + a1*b0
c2 = a1*b1
```

## Board result

```text
compute latency                 997.56 us/ciphertext
compute throughput             1002.45 EvalMultNoRelin/s
profile-inclusive latency      1005.92 us/ciphertext
profile-inclusive throughput    994.12 EvalMultNoRelin/s
stream efficiency                98.5-98.6%
```

Per-pair batch-384 medians:

```text
pair 0   63882.82 us
pair 1   63810.86 us
pair 2   63822.52 us
pair 3   63877.93 us
pair 4   63853.16 us
pair 5   63815.16 us
```

## OpenFHE software baseline

The vector-generation run measured:

```text
OpenFHE EvalMultNoRelin         1106.30 us/ciphertext
```

Measured speedups:

```text
FPGA compute vs OpenFHE         1.1090x
FPGA end-to-end vs OpenFHE      1.0998x
```

That corresponds to:

```text
compute latency reduction        9.83%
end-to-end latency reduction      9.07%
```

## Architecture

```text
EvalMul3 arithmetic core        100 MHz
DMA MM2S/S2MM memory side       150 MHz
PS HP0/HP1                      150 MHz
stream CDC FIFOs                1024 words each
MM2S/S2MM DRE                   disabled
DMA burst length                16 beats
```

The 100 MHz arithmetic ceiling remains:

```text
983.04 us/ciphertext
1017.25 EvalMultNoRelin/s
```

The measured compute result reaches:

```text
98.55% of the architectural ceiling
```

## Physical implementation

```text
WNS                              +0.263 ns
failing timing paths             0
LUTs                             7,840
registers                        8,690
DSP48E1                          128
RAMB18E1                         4
RAMB36E1                         4
bitstream                        complete
```

## Progression

```text
coefficient-domain FPGA         5951.00 us/ciphertext
fused 100 MHz, batch 32         1200.56 us/ciphertext
fused 100 MHz, batch 256        1057.98 us/ciphertext
dual-clock, batch 256           1004.15 us/ciphertext
dual-clock, batch 384            997.56 us/ciphertext
```

The final design is approximately `5.97x` faster than the previous
coefficient-domain FPGA path and is the first measured checkpoint above
1,000 exact encrypted `EvalMultNoRelin` operations per second.
