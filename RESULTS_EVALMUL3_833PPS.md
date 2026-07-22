# PYNQ-Z2 fused OpenFHE EvalMultNoRelin milestone

## Result

The FPGA now performs an exact, real encrypted BGVRNS
`EvalMultNoRelin` directly in OpenFHE's evaluation domain.

Test case:

```text
ring dimension       4096
ciphertext inputs    32 encrypted pairs
input components     2 per ciphertext
output components    3 per ciphertext
RNS towers           12
tower pairs          6
verified components  1152 tower-components
```

Every FPGA result matched OpenFHE exactly:

```text
c0 = a0*b0
c1 = a0*b1 + a1*b0
c2 = a1*b1
```

## Board performance

Per-pair batch-32 medians:

```text
pair 0: 6446.87 us
pair 1: 6395.41 us
pair 2: 6389.48 us
pair 3: 6394.67 us
pair 4: 6403.81 us
pair 5: 6387.59 us
```

Aggregate twelve-tower result:

```text
FPGA compute latency       1200.56 us/ciphertext
FPGA compute throughput     832.95 ciphertexts/s

FPGA profile-inclusive     1297.67 us/ciphertext
FPGA end-to-end throughput  770.61 ciphertexts/s
```

OpenFHE's earlier batch-32 baseline on the same workload was:

```text
1426.94 us/ciphertext
700.80 ciphertexts/s
```

Speedups:

```text
FPGA compute vs OpenFHE       1.1886x
FPGA end-to-end vs OpenFHE    1.0996x
```

The fused architecture is also approximately `4.96x` faster than the prior
coefficient-domain FPGA bridge, which required forward and inverse NTTs around
each DCRT product.

## Standalone physical core

```text
clock             100 MHz
WNS               +0.165 ns
failing paths     0
LUTs              4,135
registers         3,673
DSP48E1           128
RAMB18E1          0
RAMB36E1          0
```

## Complete DMA overlay

```text
clock             100 MHz
WNS               +0.257 ns
failing paths     0
LUTs              8,073
registers         7,958
DSP48E1           128
RAMB18E1          2
RAMB36E1          2
```

## Architecture

Each coefficient launches all four ciphertext products concurrently for two
RNS towers:

```text
two towers
x four modular products
= eight II=1 Barrett multiplier pipelines
```

The design contains no coefficient or twiddle BRAM and performs no forward or
inverse NTT.

The input-bandwidth ceiling at 100 MHz is:

```text
4 * 4096 = 16384 clocks per tower pair
6 * 163.84 us = 983.04 us per twelve-tower ciphertext
1017.25 ciphertexts/s
```

The batch-32 physical run reached `81.9%` of that compute ceiling. The next
checkpoint measures larger batches to distinguish fixed DMA transaction
overhead from sustained HP-port bandwidth loss.
