# pynq_butterfly

An exact FPGA accelerator for [OpenFHE](https://github.com/openfheorg/openfhe-development)
BGVRNS ciphertext multiplication and BV relinearization on a PYNQ-Z2
(`XC7Z020`).

The current design accepts evaluation-domain OpenFHE ciphertext components,
computes the dense modular arithmetic for ciphertext multiplication, performs
BV key-switch multiply-accumulate, adds the key-switch result into the two
surviving ciphertext components, and returns an exact two-component
relinearized ciphertext.

For ring dimension `N = 4096`, 12 Q towers, and 12 BV digits, the PYNQ-Z2
implementation now narrowly exceeds the measured OpenFHE 1.5.1 software
`EvalMult` rate in a zero-copy steady-state FPGA session.

## Headline result

The persistent-output, coefficient-major BV overlay processes a batch of 64
ciphertexts at **245.61 exact relinearized ciphertexts per second**:

| Metric | FPGA result | OpenFHE 1.5.1 reference |
| --- | ---: | ---: |
| Ring dimension | `4096` | `4096` |
| Q towers | `12` | `12` |
| BV digits | `12` | `12` |
| Ciphertexts per batch | `64` | `1` per measured call |
| Steady-state session latency | **4071.50 us/ciphertext** | `4083.78 us/ciphertext` |
| Steady-state throughput | **245.61 ciphertexts/s** | `244.87 ciphertexts/s` |
| FPGA advantage | **0.30%** | — |
| Exact residue words checked | **6,291,456** | — |
| Mismatches | **0** | — |

The measured six-pair session was:

```text
median_dma_call_us=260456.91
median_session_wall_us=260576.14
median_copy_flush_us=0.00
median_dispatch_gap_us=122.83
session_wall_us_per_relinearized_EvalMult=4071.50
session_wall_relinearized_EvalMult_per_second=245.61
```

The input stream ceiling at this batch size is `248.49 ciphertexts/s`, so the
complete measured session reaches **98.84%** of the architectural input-rate
limit.

### Scope of the performance claim

This is a real no-copy FPGA session-wall measurement: all six input pair frames
were already resident in CMA buffers, one persistent S2MM output transfer was
armed, six MM2S transfers were submitted, and the final receive completion was
included in the timed interval.

The following work remains outside the timed steady-state session:

- host-side BV CRT decomposition of the third ciphertext component;
- one-time construction and packing of the reusable coefficient-major frames;
- OpenFHE key generation and encryption.

The current result therefore establishes a steady-state win for the implemented
FPGA multiplication and BV key-switch arithmetic path. It is not yet a claim
that a fresh application-level ciphertext operation, including host
decomposition and packing, is faster end to end.

## Physical implementation

The complete dual-clock PYNQ-Z2 overlay closes timing with the persistent-output
multi-pair session wrapper:

| Resource | Result |
| --- | ---: |
| Arithmetic/core clock | `100 MHz` |
| DMA and PS HP-port clock | `150 MHz` |
| Worst negative slack | `+0.040 ns` |
| Failing timing paths | `0` |
| LUTs | `11,084` |
| Registers | `11,488` |
| DSP48E1 | `160` |
| RAMB18E1 | `4` |
| RAMB36E1 | `4` |
| SRLs | `992` |

The arithmetic core itself uses ten initiation-interval-one Barrett pipelines:

```text
c0 products:                 2 pipelines
c1 cross products:           4 pipelines
BV key-switch b products:    2 pipelines
BV key-switch a products:    2 pipelines
                              -----------
total:                       10 pipelines
```

Each 32-bit modular multiplier maps to 16 DSP48E1 blocks, giving the exact
`160 DSP48E1` total.

## Arithmetic

OpenFHE ciphertext components are already in `Format::EVALUATION`, so the
accelerator does not perform forward or inverse NTTs around each ciphertext
multiplication.

For every coefficient and Q tower, multiplication begins with:

```text
c0 = a0 * b0 mod q
c1 = a0 * b1 + a1 * b0 mod q
c2 = a1 * b1 mod q
```

BV relinearization decomposes `c2` into CRT digits and evaluates:

```text
ks_b = sum_j digit_j * eval_key_b_j mod q
ks_a = sum_j digit_j * eval_key_a_j mod q

relin_c0 = c0 + ks_b mod q
relin_c1 = c1 + ks_a mod q
```

The current transport boundary supplies the exact BV CRT digits from the host.
Because `c2` is consumed by that host decomposition boundary, the final
coefficient-major core does not spend FPGA multipliers recomputing an unused
`c2` stream. All dense modular multiplication, accumulation, and final
component addition after the supplied decomposition are performed in RTL.

Two adjacent Q towers are packed into every 64-bit AXI4-Stream word:

```text
bits 31:0   lower-numbered tower
bits 63:32  higher-numbered tower
```

## Coefficient-major evaluation-key reuse

The evaluation key is identical across every ciphertext in a batch. Sending it
once per coefficient and digit instead of once per ciphertext changes the
external input cost from:

```text
legacy repeated-key protocol: 40B words per coefficient
coefficient-major protocol:   16B + 24 words per coefficient
```

At batch 64:

```text
legacy:             2560 words/coefficient/pair
coefficient-major:  1048 words/coefficient/pair
input reduction:    59.0625%
```

The core uses two coefficient banks. While one bank drains completed modular
products and emits results, the other accepts the next coefficient. Independent
per-bank completion counters prevent a bank from becoming output-ready before
both its EvalMult products and final BV accumulator writes have committed.

A one-cycle register boundary separates BV metadata lookup and accumulator
read from the modular-add carry chain and accumulator write. That timing split
was the change that turned the ping-pong design from a marginal failing path
into a robust 100 MHz implementation.

## Persistent six-pair session

The complete 12-tower ciphertext is processed as six paired-tower input frames.
A profile table stores all six modulus and Barrett-reciprocal pairs.

The session keeps one S2MM output transfer active across the complete operation:

```text
one RLPT profile-table load
one persistent S2MM receive transfer
six RLMP MM2S pair transfers
one final output TLAST after pair six
```

Intermediate child-core `TLAST` markers are suppressed. Output order remains
pair-major, coefficient-major, ciphertext-major, with `relin_c0` followed by
`relin_c1`.

### `RLPT` — load the six paired-tower profiles

```text
word 0: command = 0x524c5054
word 1: duplicated pair count

for every pair:
    {q1, q0}
    {mu1, mu0}

final mu word carries TLAST
```

### `RLMP` — process one indexed pair inside a persistent output session

```text
word 0: command = 0x524c4d50
word 1: {digit_count, ciphertext_count}
word 2: {pair_count, pair_index}

for every coefficient:
    for every ciphertext:
        a0, a1, b0, b1

    for every digit:
        eval_key_b, eval_key_a
        one digit word for every ciphertext
```

The six pair frames remain separate because the AXI DMA length register is 26
bits wide. The combined B64 input would exceed that limit, while every
individual pair frame remains legal.

## CMA configuration

The stock PYNQ image reserves only 128 MiB for CMA:

```text
CONFIG_CMA_SIZE_MBYTES=128
```

The B64 no-copy workload requires approximately:

```text
six MM2S pair buffers:  196.50 MiB
one S2MM output buffer:  24.00 MiB
total:                  220.50 MiB
```

The successful board run used the kernel command-line override:

```text
cma=288M
```

On this PYNQ image, `/boot/boot.scr` imports `/boot/uEnv.txt` before booting
`image.ub`. The working `uEnv.txt` boot arguments were:

```text
bootargs=root=/dev/mmcblk0p2 rw earlyprintk rootfstype=ext4 rootwait devtmpfs.mount=1 uio_pdrv_genirq.of_id=generic-uio clk_ignore_unused cma=288M
```

After reboot:

```text
CmaTotal: 294912 kB
```

A single 196.5 MiB CMA arena still failed as one contiguous allocation, but six
separate prefilled CMA MM2S buffers plus the 24 MiB S2MM buffer succeeded. The
measured winning run therefore reported:

```text
send_buffer_mode=all-cma
median_copy_flush_us=0.00
```

## Exactness

Validation uses real encrypted OpenFHE BGVRNS ciphertexts and evaluation keys.
The probe and bridge establish each boundary independently:

1. OpenFHE `EvalMultNoRelin` produces three evaluation-domain components.
2. `KeySwitchCore` exactly equals `KeySwitchPrecomputeCore` followed by
   `EvalFastKeySwitchCore`.
3. Manual additions of the key-switch outputs into `c0` and `c1` exactly equal
   OpenFHE `EvalMult`.
4. The FPGA result is compared coefficient by coefficient against those exact
   OpenFHE relinearized outputs.

The B64 milestone checks:

```text
12 towers
x 4096 coefficients
x 64 ciphertexts
x 2 output components
= 6,291,456 exact residue comparisons
```

Every comparison passed.

## Performance progression

| Checkpoint | Latency | Throughput |
| --- | ---: | ---: |
| Earlier coefficient-domain FPGA bridge | `5951.00 us/ct` | `168.04 ct/s` |
| Evaluation-domain `EvalMultNoRelin`, single-clock B32 | `1200.56 us/ct` | `832.95 ct/s` |
| Evaluation-domain all-pair `EvalMultNoRelin`, B64 | `998.50 us/ct` | `1001.51 ct/s` |
| First fused BV board protocol, repeated keys B8 | `10944.06 us/ct` | `91.37 ct/s` |
| Coefficient-major serialized B64 | `4685.22 us/ct` | `213.44 ct/s` |
| Ping-pong coefficient-major B64 | `4196.49 us/ct` | `238.29 ct/s` |
| Compute-drain overlap B64 | `4158.25 us/ct` | `240.49 ct/s` |
| Persistent output, no-copy B64 | **`4071.50 us/ct`** | **`245.61 ct/s`** |

The earlier `EvalMultNoRelin` line remains the high-throughput path when a
three-component unrelinearized ciphertext is acceptable. The current front
line focuses on exact fused BV relinearization.

## Quick start

Current development is on:

```text
branch: evalmul-relinearization
```

### 1. Build the OpenFHE probe and vectors

The OpenFHE bridge targets OpenFHE 1.5.1 and exports the encrypted inputs,
BV decomposition digits, evaluation-key towers, key-switch references, and
final relinearized ciphertext components.

```bash
cd openfhe_eval_domain_bridge
./build.sh
cd ..
```

### 2. Build the PYNQ-Z2 overlay

Vivado 2024.1 is expected. The dual-clock build uses the PYNQ-Z2 board part,
a 100 MHz arithmetic domain, and a 150 MHz DMA/HP-port domain.

The implementation Tcl is under:

```text
scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.tcl
```

Deployment artifacts are placed under:

```text
deploy/bv_keyreuse_multi_pair_session_dma150/
```

### 3. Configure CMA

Create `/boot/uEnv.txt` with the boot arguments shown in the CMA section and
reboot. Confirm:

```bash
grep -E 'CmaTotal|CmaFree' /proc/meminfo
cat /proc/cmdline
```

### 4. Install the overlay, runner, and vectors

```bash
./install_bv_keyreuse_multi_pair_session_board.sh
```

The installer preserves existing root-owned benchmark results and stages the
vector tree before replacing the live copy.

### 5. Run the exact B64 benchmark

On the PYNQ-Z2:

```bash
sudo -i

REMOTE=/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session

"$REMOTE/run_bv_keyreuse_multi_pair_session_board.sh" \
  "$REMOTE" \
  64 \
  5 | tee "$REMOTE/results/batch_64_all_cma.log"
```

A successful no-copy run includes:

```text
PASS: every persistent-output RLMP session result matches OpenFHE
send_buffer_mode=all-cma
median_copy_flush_us=0.00
verified_residue_words=6291456
session_wall_us_per_relinearized_EvalMult=4071.50
session_wall_relinearized_EvalMult_per_second=245.61
```

## Repository layout

| Path | Contents |
| --- | --- |
| `rtl/` | exact modular arithmetic cores, coefficient-major schedulers, and AXI4-Stream wrappers |
| `tests/rtl/` | exact Icarus testbenches with deterministic output backpressure |
| `scripts/sim/` | exact RTL checkpoint launchers |
| `scripts/vivado/` | out-of-context timing sweeps and complete PYNQ-Z2 overlay builds |
| `openfhe_eval_domain_bridge/` | OpenFHE probe, vector exporter, validators, and board runners |
| `deploy/` | generated bitstreams, hardware handoffs, reports, and deployment metadata |
| `docs/` | architecture notes and historical checkpoint documentation |
| `reports/` | timing and utilization reports from development checkpoints |
| `model/` | Python golden models and earlier NTT-stage references |

## Development lineage

The repository progressed through increasingly complete OpenFHE-compatible
accelerators:

| Name | Meaning |
| --- | --- |
| `poly_mul16`, `poly_mul256`, `poly_mul4096` | early polynomial-multiplication proofs of concept |
| `runtime_profile` | runtime-loadable modulus and NTT profiles |
| `two_tower_parallel` | two RNS towers packed into one 64-bit stream |
| `four_butterfly` | four-butterfly coefficient-domain DSP development line |
| `evalmul3` | fused evaluation-domain three-component ciphertext product |
| `evalmul3_allpairs` | cached six-pair profiles and one logical unrelinearized batch |
| `bv_keyswitch_mac` | exact two-tower BV key-switch accumulation |
| `evalmul3_bv_relinearize` | connected exact multiplication and BV relinearization |
| `bv_keyreuse_coefficient_major` | evaluation-key reuse across a ciphertext batch |
| `bv_keyreuse_pingpong` | overlapping coefficient input and output banks |
| `bv_keyreuse_drain_overlap` | overlapping the next coefficient with prior-bank compute drain |
| `bv_keyreuse_multi_pair_session` | one persistent output session across all six Q-tower pairs |

The coefficient-domain implementations remain useful as complete NTT-based
`DCRTPoly` references. The current design specializes for the representation
OpenFHE actually uses during ciphertext multiplication and concentrates the
available DSP budget on exact modular products and BV key switching.

## License

MIT — see [`LICENSE`](LICENSE).
