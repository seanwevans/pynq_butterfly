# pynq_butterfly

An exact FPGA accelerator for [OpenFHE](https://github.com/openfheorg/openfhe-development)
BGVRNS ciphertext multiplication on a PYNQ-Z2 (`XC7Z020`).

The current design computes OpenFHE `EvalMultNoRelin` directly in the
evaluation domain for ring dimension `N = 4096`. It accepts two ciphertexts
with components `(a0, a1)` and `(b0, b1)` and produces the unrelinearized
three-component result

```text
c0 = a0 * b0
c1 = a0 * b1 + a1 * b0
c2 = a1 * b1
```

independently in every RNS tower, with exact bit-for-bit agreement against
OpenFHE on real hardware.

## Headline result

The dual-clock evaluation-domain overlay exceeds **1,000 exact encrypted
`EvalMultNoRelin` operations per second** on a PYNQ-Z2:

| Metric | Result |
| --- | ---: |
| Ring dimension | `4096` |
| RNS towers | `12` |
| Ciphertexts per batch | `384` |
| FPGA compute latency | **997.56 us/ciphertext** |
| FPGA compute throughput | **1002.45 ciphertexts/s** |
| Profile-inclusive latency | **1005.92 us/ciphertext** |
| Profile-inclusive throughput | **994.12 ciphertexts/s** |
| OpenFHE software reference | `1106.30 us/ciphertext` |
| FPGA compute speedup | **1.109x** |
| Verified tower-components | `13,824` |
| Mismatches | **0** |

The arithmetic core reaches **98.55%** of its 100 MHz architectural stream
ceiling:

```text
983.04 us/ciphertext
1017.25 ciphertexts/s
```

## Physical implementation

The current `evalmul3` overlay closes timing with separate core and memory
clock domains:

| Resource | Result |
| --- | ---: |
| Arithmetic/core clock | `100 MHz` |
| DMA and PS HP-port clock | `150 MHz` |
| Worst negative slack | `+0.263 ns` |
| Failing timing paths | `0` |
| LUTs | `7,840` |
| Registers | `8,690` |
| DSP48E1 | `128` |
| RAMB18E1 | `4` |
| RAMB36E1 | `4` |

## Architecture

OpenFHE ciphertext components are already in `Format::EVALUATION`, so the
current accelerator does not perform forward or inverse NTTs around each
ciphertext multiplication.

For each coefficient and each pair of RNS towers, the core launches four
modular products:

```text
p00 = a0 * b0
p01 = a0 * b1
p10 = a1 * b0
p11 = a1 * b1

c0 = p00
c1 = p01 + p10 mod q
c2 = p11
```

Two towers are packed into each 64-bit AXI4-Stream word:

```text
bits 31:0   tower 0
bits 63:32  tower 1
```

The datapath contains eight initiation-interval-one Barrett pipelines:

```text
4 ciphertext products
x 2 RNS towers
= 8 modular multipliers launched per coefficient
```

### Dual-clock transport

The arithmetic core remains at 100 MHz while DMA and the Zynq high-performance
ports run at 150 MHz:

```text
DDR / PS HP0
    |
AXI DMA MM2S, 150 MHz
    |
1024-word asynchronous AXI4-Stream FIFO
    |
EvalMul3 core, 100 MHz
    |
1024-word asynchronous AXI4-Stream FIFO
    |
AXI DMA S2MM, 150 MHz
    |
DDR / PS HP1
```

Both DMA data realignment engines are disabled because the PYNQ buffers and
transfer lengths are 64-bit aligned. MM2S and S2MM use 16-beat bursts, matching
the Zynq-7000 HP-port limit.

## Performance progression

| Checkpoint | Compute latency | Throughput |
| --- | ---: | ---: |
| Earlier coefficient-domain FPGA bridge | `5951.00 us/ct` | `168.04 ct/s` |
| Fused evaluation-domain, batch 32 | `1200.56 us/ct` | `832.95 ct/s` |
| Fused evaluation-domain, batch 256 | `1057.98 us/ct` | `945.20 ct/s` |
| Dual-clock transport, batch 256 | `1004.15 us/ct` | `995.87 ct/s` |
| Dual-clock transport, batch 384 | **`997.56 us/ct`** | **`1002.45 ct/s`** |

The current design is approximately **5.97x faster** than the previous
coefficient-domain FPGA path.

## Exactness

Validation uses real encrypted OpenFHE BGVRNS ciphertexts.

For every test batch, the host bridge:

1. creates and encrypts OpenFHE plaintexts;
2. obtains the evaluation-domain DCRT tower data for `a0`, `a1`, `b0`, and
   `b1`;
3. computes OpenFHE `EvalMultNoRelin`;
4. exports DMA input frames and exact expected `c0`, `c1`, and `c2` tower
   values;
5. compares every FPGA output coefficient against OpenFHE.

The batch-384 milestone verifies:

```text
384 ciphertext multiplications
x 12 towers
x 3 output components
= 13,824 exact tower-component comparisons
```

## Quick start

The current work is on:

```text
branch: evalmul3-dma-throughput
tag:    pynq-z2-evalmul3-1002pps
```

### 1. Build the OpenFHE bridge

```bash
cd openfhe_eval_domain_bridge
./build.sh
cd ..
```

### 2. Generate a 12-tower batch-384 workload

```bash
./prepare_evalmul3_batch_sweep.sh 12 384
```

This writes:

```text
openfhe_eval_domain_bridge/vectors/t12_c384/
```

### 3. Build the PYNQ-Z2 overlay

Vivado 2024.1 is expected. The provided launcher is written for WSL with
Vivado installed on Windows.

```bash
./build_evalmul3_dma150_overlay.sh
```

Generated deployment artifacts are placed under:

```text
deploy/evalmul3_two_tower_dma150/
```

### 4. Copy the overlay and vectors to the board

```bash
./install_evalmul3_dma150_board.sh \
  openfhe_eval_domain_bridge/vectors/t12_c384 \
  xilinx@pynq \
  /home/xilinx/jupyter_notebooks/evalmul3_dma150_c384
```

### 5. Run the exact board benchmark

On the PYNQ-Z2:

```bash
sudo -i

/home/xilinx/jupyter_notebooks/evalmul3_dma150_c384/run_evalmul3_dma150_board.sh \
  /home/xilinx/jupyter_notebooks/evalmul3_dma150_c384 \
  384 \
  7
```

A successful run ends with output similar to:

```text
PASS: every fused evaluation-domain component matches OpenFHE
verified_tower_components=13824
compute_us_per_EvalMultNoRelin=997.56
compute_EvalMultNoRelin_per_second=1002.45
```

## Commands and wire protocol

The fused core uses two AXI4-Stream commands.

### `EVPF` — load a paired-tower modulus profile

```text
word 0: command = 0x45565046
word 1: {q1, q0}
word 2: {mu1, mu0}, TLAST
```

### `EVB3` — multiply a batch of two-component ciphertexts

```text
word 0: command = 0x45564233
word 1: duplicated ciphertext count
remaining input:
    coefficient-major a0, a1, b0, b1 paired-tower words

output:
    coefficient-major c0, c1, c2 paired-tower words
    final c2 word carries TLAST
```

One bitstream supports arbitrary 32-bit RNS moduli by loading a new paired
profile before each tower-pair batch.

## Repository layout

| Path | Contents |
| --- | --- |
| `rtl/` | SystemVerilog arithmetic cores and AXI4-Stream wrappers |
| `tests/rtl/` | exact Icarus testbenches, including output-backpressure tests |
| `scripts/sim/` | RTL simulation launchers |
| `scripts/vivado/` | out-of-context and complete PYNQ-Z2 overlay build Tcl |
| `openfhe_eval_domain_bridge/` | OpenFHE ciphertext generator, exporter, validator, and PYNQ runner |
| `deploy/evalmul3_two_tower_dma150/` | deployment metadata, reports, and board runner |
| `model/` | Python golden models and historical NTT-stage vectors |
| `tests/board/` | board tests for earlier multiplier variants |
| `scripts/package/` | packaging flows for earlier packaged-IP overlays |
| `scripts/integrate/` | integration flows for earlier coefficient-domain overlays |
| `reports/` | timing and utilization reports from development checkpoints |
| `docs/` | architecture notes and historical checkpoint documentation |
| `profiles/` | OpenFHE modulus and root profiles |
| `vivado/` | constraints and older implementation studies |

## Simulation

Run the fused evaluation-domain checkpoint:

```bash
./run_eval_domain_fused_checkpoint.sh
```

This performs:

- OpenFHE generation and exact software comparison;
- Icarus simulation of the paired-tower `EvalMultNoRelin` core;
- deterministic output-backpressure testing.

The broader historical regression suite remains available:

```bash
scripts/run_sim_regression.sh --quick
scripts/run_sim_regression.sh --all
```

## Development lineage

The repository began with small polynomial-multiplication demonstrations and
progressed through increasingly complete OpenFHE-compatible overlays:

| Name | Meaning |
| --- | --- |
| `poly_mul16`, `poly_mul256` | early AXI-Lite and AXI4-Stream proofs of concept |
| `poly_mul4096` | first `N = 4096` multiplier |
| `runtime_profile` | runtime-loadable modulus and NTT profiles |
| `two_tower_parallel` | two RNS towers packed into one 64-bit stream |
| `dual_butterfly` | two coefficient-domain butterflies per tower |
| `db2b` | arbitrary-count coefficient-domain batching |
| `db2p` | operand prefetch |
| `db2r` | buffered result handoff |
| `four_butterfly` | four-butterfly DSP Barrett development line |
| `evalmul3` | fused evaluation-domain three-component ciphertext product |
| `evalmul3_dma150` | current dual-clock, no-DRE transport overlay |

The earlier coefficient-domain designs remain useful as complete NTT-based
`DCRTPoly` multiplier references. The current front line specializes the
hardware for the representation OpenFHE actually uses during ciphertext
multiplication and removes the unnecessary NTT round trips.

## License

MIT — see [`LICENSE`](LICENSE).
