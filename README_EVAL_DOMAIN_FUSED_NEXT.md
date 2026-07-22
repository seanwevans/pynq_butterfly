# Fused evaluation-domain ciphertext checkpoint

This checkpoint removes the unnecessary forward and inverse NTTs from
encrypted OpenFHE ciphertext multiplication.

The previous exact bridge established:

```text
A = (a0, a1)
B = (b0, b1)

c0 = a0*b0
c1 = a0*b1 + a1*b0
c2 = a1*b1
```

OpenFHE ciphertext components are already stored in `Format::EVALUATION`.
Therefore each multiplication above is a pointwise modular multiplication,
not a complete negacyclic polynomial multiplication.

## New datapath

For each coefficient and each of two RNS towers, the core launches four
Barrett multipliers concurrently:

```text
p00 = a0*b0
p01 = a0*b1
p10 = a1*b0
p11 = a1*b1

c0 = p00
c1 = p01+p10 mod q
c2 = p11
```

The core reuses the already-proven seven-cycle, II=1
`modmul_barrett60_pipeline_split_core`. It contains:

- eight Barrett multiplier instances;
- no coefficient BRAM;
- no twiddle BRAM;
- no NTT schedule;
- an eight-entry result FIFO;
- AXI input/output overlap;
- credit-based backpressure for arbitrary output stalls.

## Protocol

Paired tower word:

```text
bits 31:0   tower 0
bits 63:32  tower 1
```

Three-word profile:

```text
EVPF
q
mu=floor(2^60/q)
```

Batch:

```text
EVB3
ciphertext_count

for ciphertext:
  for coefficient 0..4095:
    a0
    a1
    b0
    b1
```

Output:

```text
for ciphertext:
  for coefficient 0..4095:
    c0
    c1
    c2
```

## Apply

From the repository root:

```bash
git switch -c eval-domain-ciphertext-fused

unzip -o \
  eval_domain_ciphertext_fused_checkpoint.zip
```

The ZIP adds new files only.

## Run the checkpoint

```bash
cd /mnt/f/repos/pynq_butterfly

./run_eval_domain_fused_checkpoint.sh 12 4
```

This performs two independent gates:

1. OpenFHE creates real encrypted BGVRNS ciphertexts and proves that the fused
   evaluation-domain equations equal `EvalMultNoRelin` exactly.
2. Icarus Verilog runs the two-tower AXI core with deterministic output
   backpressure and checks every `c0`, `c1`, and `c2` word exactly.

Expected software output:

```text
PASS: all input components remained in evaluation format
PASS: c0=a0*b0 exactly in evaluation format
PASS: c1=a0*b1+a1*b0 exactly in evaluation format
PASS: c2=a1*b1 exactly in evaluation format
PASS: fused components equal OpenFHE EvalMultNoRelin
```

Expected RTL output:

```text
PASS: fused two-tower evaluation-domain c0/c1/c2 exact
PASS: deterministic AXI output backpressure tolerated
```

## Hardware ceiling

At 100 MHz, one tower pair consumes:

```text
4 * 4096 = 16384 clocks/ciphertext
163.84 us/ciphertext
```

A twelve-tower ciphertext uses six tower pairs:

```text
6 * 163.84 us = 983.04 us/ciphertext
1017.25 ciphertexts/s
```

The next checkpoint is Vivado IP packaging, DMA overlay integration, timing
closure at 100 MHz, and the first physical `EVB3` board benchmark.
