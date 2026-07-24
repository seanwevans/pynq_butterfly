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
| Ciphertexts per batch | `64` |
| FPGA compute latency | **998.50 us/ciphertext** |
| FPGA compute throughput | **1001.51 ciphertexts/s** |
| Profile-inclusive latency | **1006.69 us/ciphertext** |
| Profile-inclusive throughput | **993.36 ciphertexts/s** |
| OpenFHE software reference | `1106.30 us/ciphertext` |
| FPGA compute speedup | **1.108x** |
| Verified tower-components | `2,304` |
| Mismatches | **0** |

The arithmetic core reaches **98.45%** of its 100 MHz architectural stream
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
| Worst negative slack | `+0.027 ns` |
| Failing timing paths | `0` |
| LUTs | `8,507` |
| Registers | `9,846` |
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

A profile-table sequencer now caches all six paired-tower modulus profiles.
One external `EV12` frame contains the complete 12-tower batch. The sequencer
feeds each pair to the unchanged arithmetic core, suppresses intermediate
`TLAST` markers, and emits one final frame boundary after pair six.

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
| Dual-clock all-pair frame, batch 64 | **`998.50 us/ct`** | **`1001.51 ct/s`** |

At batch 64, replacing six software-visible DMA transactions with one
all-pair frame improved the earlier dual-clock result from `1122.52 us/ct`
(`890.86 ct/s`) to `998.50 us/ct` (`1001.51 ct/s`).

The current design is approximately **5.96x faster** than the previous
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

The all-pair batch-64 milestone verifies:

```text
64 ciphertext multiplications
x 12 towers
x 3 output components
= 2,304 exact tower-component comparisons
```

## Quick start

The current work is on:

```text
branch: evalmul3-all-pair-frame
tag:    pynq-z2-evalmul3-allpairs-1001pps
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
./build_evalmul3_allpairs_dma150_overlay.sh
```

Generated deployment artifacts are placed under:

```text
deploy/evalmul3_allpairs_dma150/
```

### 4. Copy the overlay and vectors to the board

```bash
./install_evalmul3_allpairs_board.sh \
  openfhe_eval_domain_bridge/vectors/t12_c384 \
  xilinx@pynq \
  /home/xilinx/jupyter_notebooks/evalmul3_allpairs
```

### 5. Run the exact board benchmark

On the PYNQ-Z2:

```bash
sudo -i

/home/xilinx/jupyter_notebooks/evalmul3_allpairs/run_evalmul3_allpairs_board.sh \
  /home/xilinx/jupyter_notebooks/evalmul3_allpairs \
  64 \
  7
```

A successful run ends with output similar to:

```text
PASS: every EV12 fused evaluation-domain component matches OpenFHE
verified_tower_components=2304
compute_us_per_EvalMultNoRelin=998.50
compute_EvalMultNoRelin_per_second=1001.51
```

## Commands and wire protocol

The external DMA interface uses two all-pair commands.

### `EVPT` — load the paired-tower profile table

```text
word 0: command = 0x45565054
word 1: duplicated pair count

for every pair:
    {q1, q0}
    {mu1, mu0}

the final mu word carries TLAST
```

### `EV12` — multiply every loaded tower pair

```text
word 0: command = 0x45563132
word 1: {pair_count, ciphertext_count}

pair-major input:
    for every pair, ciphertext, and coefficient:
        a0, a1, b0, b1

pair-major output:
    c0, c1, c2

only the final c2 word of the final pair carries TLAST
```

The sequencer stores up to six paired profiles and internally emits the proven
legacy `EVPF` and `EVB3` frames for the two-tower arithmetic core. One bitstream
therefore supports arbitrary compatible RNS chains while software performs only
one batch DMA transaction.

## Repository layout

| Path | Contents |
| --- | --- |
| `rtl/` | SystemVerilog arithmetic cores and AXI4-Stream wrappers |
| `tests/rtl/` | exact Icarus testbenches, including output-backpressure tests |
| `scripts/sim/` | RTL simulation launchers |
| `scripts/vivado/` | out-of-context and complete PYNQ-Z2 overlay build Tcl |
| `openfhe_eval_domain_bridge/` | OpenFHE ciphertext generator, exporter, validator, and PYNQ runner |
| `deploy/evalmul3_allpairs_dma150/` | deployment metadata, reports, and board runner |
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
./run_evalmul3_allpairs_checkpoint.sh
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
| `evalmul3_dma150` | dual-clock, no-DRE transport overlay |
| `evalmul3_allpairs` | cached profile table and one logical DMA frame for every RNS pair |

The earlier coefficient-domain designs remain useful as complete NTT-based
`DCRTPoly` multiplier references. The current front line specializes the
hardware for the representation OpenFHE actually uses during ciphertext
multiplication and removes the unnecessary NTT round trips.

## License

MIT — see [`LICENSE`](LICENSE).
