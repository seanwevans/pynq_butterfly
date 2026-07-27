# pynq_butterfly

An exact FPGA accelerator for [OpenFHE](https://github.com/openfheorg/openfhe-development)
BGVRNS ciphertext multiplication and BV relinearization on a PYNQ-Z2 (`XC7Z020`).

## Repository contract

The repository root is reserved for primary project metadata, design and result
documentation, and a deliberately small compatibility surface.  Maintained
automation is owned by the functional directories under [`scripts/`](scripts/README.md);
new commands must not be added at the root.

The supported workflow entry points for the headline overlay are:

```bash
scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.sh
scripts/board/install/install_bv_keyreuse_multi_pair_session_board.sh VECTOR_DIRECTORY
scripts/run_sim_regression.sh
```

For existing callers, the following root commands remain as compatibility entry
points.  They print a deprecation notice and delegate to the maintained command:

```bash
./build_bv_keyreuse_multi_pair_session_dma150_overlay.sh
./install_bv_keyreuse_multi_pair_session_board.sh VECTOR_DIRECTORY
```

All other commands should be invoked at their documented path under `scripts/`.
Files in `scripts/archive/` describe past, narrowly scoped repository-repair and
release procedures and are **not** supported automation.

The accelerator accepts evaluation-domain OpenFHE ciphertext components, computes
the dense modular arithmetic for ciphertext multiplication, performs BV key-switch
multiply-accumulate, adds the key-switch result into the two surviving ciphertext
components, and returns an exact two-component relinearized ciphertext.

Every result below is a real board measurement on a PYNQ-Z2, validated
coefficient-by-coefficient against OpenFHE 1.5.1 output. Utilization and timing
figures come from routed Vivado builds whose `build_summary.txt` files are
committed under `deploy/`.

## Headline result

For ring dimension `N = 4096`, 12 Q towers, and 12 BV digits, the
persistent-output coefficient-major BV overlay processes a batch of 64
ciphertexts at **245.61 exact relinearized ciphertexts per second**.

| Metric | FPGA | OpenFHE 1.5.1 reference |
| --- | ---: | ---: |
| Ring dimension | `4096` | `4096` |
| Q towers | `12` | `12` |
| BV digits | `12` | `12` |
| Ciphertexts per batch | `64` | `1` per measured call |
| Steady-state session latency | **`4071.50 us/ct`** | `4083.78 us/ct` |
| Steady-state throughput | **`245.61 ct/s`** | `244.87 ct/s` |
| Exact residue words checked | **`6,291,456`** | — |
| Mismatches | **`0`** | — |

The measured six-pair session:

```text
median_dma_call_us=260456.91
median_session_wall_us=260576.14
median_copy_flush_us=0.00
median_dispatch_gap_us=122.83
session_wall_us_per_relinearized_EvalMult=4071.50
session_wall_relinearized_EvalMult_per_second=245.61
```

The architectural input-stream ceiling at this batch size is `248.49 ct/s`
(derived ahead of implementation in
[`NEXT_EVAL_KEY_REUSE_ARCHITECTURE.md`](NEXT_EVAL_KEY_REUSE_ARCHITECTURE.md)),
so the complete session reaches **98.84%** of the transport limit.

### How to read the comparison

This is a real no-copy FPGA session-wall measurement. All six input pair frames
were resident in CMA buffers, one persistent S2MM output transfer was armed, six
MM2S transfers were submitted, and the final receive completion was inside the
timed interval. The FPGA figure is a median over repeated runs.

Two honest caveats:

**The margin is smaller than the measurement resolves.** The OpenFHE reference
is currently timed as a single `EvalMult` call with no warm-up and no
repetition, while the FPGA side is a median of repeated batched runs. On a
Cortex-A9, first-call effects — allocator behaviour, cold instruction cache,
lazy table initialization — are plausibly larger than the 0.30% gap. Treat the
two figures as *parity*, not as a demonstrated FPGA win, until the reference is
re-measured over many warmed iterations.

**Work outside the timed session.** The following are not included:

- host-side BV CRT decomposition of the third ciphertext component;
- one-time construction and packing of the reusable coefficient-major frames;
- OpenFHE key generation and encryption.

The result establishes steady-state parity for the implemented FPGA
multiplication and BV key-switch arithmetic path. It is not a claim that a
fresh application-level ciphertext operation, including host decomposition and
packing, is faster end to end.

## Physical implementation

All overlays are dual-clock: a 100 MHz arithmetic domain and a 150 MHz DMA/PS
HP-port domain, built with Vivado 2024.1 for the PYNQ-Z2 board part using the
`Performance_ExplorePostRoutePhysOpt` strategy. Every build below routed with
zero failing timing paths.

| Generation | WNS | LUT | FF | DSP48E1 | RAMB18 | RAMB36 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `evalmul3_bv_relinearized` | `+0.045` | `11,746` | `11,875` | `192` | `4` | `4` |
| `bv_keyreuse_coefficient_major` | `+0.083` | `9,838` | `9,766` | `160` | `4` | `4` |
| `bv_keyreuse_pingpong` | `+0.006` | `10,108` | `10,117` | `160` | `4` | `4` |
| `bv_keyreuse_drain_overlap` | `+0.008` | `10,143` | `10,107` | `160` | `4` | `4` |
| `bv_keyreuse_multi_pair_session` | `+0.040` | `11,084` | `11,488` | `160` | `4` | `4` |

Two things worth noting in that table. DSP count is flat at 160 across every
coefficient-major generation while throughput climbs from 213 to 245 ct/s —
all of that gain came from scheduling and transport restructuring at fixed
arithmetic cost. And the ping-pong generation closed at `+0.006 ns`; the
accumulator pipeline split described in
[`README_BV_KEYREUSE_PINGPONG_ACCUMULATOR_PIPELINE.md`](README_BV_KEYREUSE_PINGPONG_ACCUMULATOR_PIPELINE.md)
is what recovered slack while the session wrapper was still being added.

The 160-DSP arithmetic core is ten initiation-interval-one Barrett pipelines:

```text
c0 products:                 2 pipelines
c1 cross products:           4 pipelines
BV key-switch b products:    2 pipelines
BV key-switch a products:    2 pipelines
                              -----------
total:                      10 pipelines
```

Each 32-bit modular multiplier maps to 16 DSP48E1 blocks.

## Arithmetic

OpenFHE ciphertext components are already in `Format::EVALUATION`, so the
accelerator performs no forward or inverse NTT around each ciphertext
multiplication.

For every coefficient and Q tower:

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

The transport boundary supplies exact BV CRT digits from the host. Because `c2`
is consumed by that host decomposition boundary, the coefficient-major core does
not spend FPGA multipliers recomputing an unused `c2` stream. All dense modular
multiplication, accumulation, and final component addition after the supplied
decomposition happen in RTL.

Two adjacent Q towers are packed into every 64-bit AXI4-Stream word:

```text
bits 31:0   lower-numbered tower
bits 63:32  higher-numbered tower
```

### Modular multiplication

[`rtl/modmul_barrett60_pipeline_split_core.sv`](rtl/modmul_barrett60_pipeline_split_core.sv)
is a fully pipelined Barrett multiplier, II=1, 7-cycle latency. The 60x31
reciprocal product is split into two parallel 30x31 products and recombined a
cycle later. Preconditions:

```text
0 < q < 2^30
a < q, b < q
mu = floor(2^60 / q)
```

Under these, `z = ab < q^2 < 2^60` and `floor(z/q) - floor(z*mu/2^60)` is 0 or 1,
so the provisional remainder is below `2q` and a **single** conditional
subtraction is sufficient. The preconditions are checked by simulation
assertions; they are not validated in hardware, and a malformed runtime profile
will silently produce wrong ciphertexts.

## Coefficient-major evaluation-key reuse

The evaluation key is identical across every ciphertext in a batch. Sending it
once per coefficient and digit rather than once per ciphertext changes the
external input cost per coefficient from `40B` words to `16B + 24`.

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

A one-cycle register boundary separates BV metadata lookup and accumulator read
from the modular-add carry chain and accumulator write. That split turned the
ping-pong design from a marginal failing path into a robust 100 MHz
implementation.

## Persistent six-pair session

A complete 12-tower ciphertext is processed as six paired-tower input frames. A
profile table stores all six modulus and Barrett-reciprocal pairs. The session
keeps one S2MM output transfer active across the whole operation:

```text
one RLPT profile-table load
one persistent S2MM receive transfer
six RLMP MM2S pair transfers
one final output TLAST after pair six
```

Intermediate child-core `TLAST` markers are suppressed. Output order is
pair-major, coefficient-major, ciphertext-major, with `relin_c0` then
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

The six pair frames stay separate because the AXI DMA length register is 26 bits
wide. A combined B64 input would exceed that; each individual pair frame is
legal.

## CMA configuration

The stock PYNQ image reserves 128 MiB for CMA. The B64 no-copy workload needs
roughly 220.5 MiB (six MM2S pair buffers at 196.5 MiB plus a 24 MiB S2MM
buffer), so the kernel command line needs an override.

On this PYNQ image `/boot/boot.scr` imports `/boot/uEnv.txt` before booting
`image.ub`. Working boot arguments:

```text
bootargs=root=/dev/mmcblk0p2 rw earlyprintk rootfstype=ext4 rootwait devtmpfs.mount=1 uio_pdrv_genirq.of_id=generic-uio clk_ignore_unused cma=288M
```

After reboot, `CmaTotal: 294912 kB`. A single 196.5 MiB contiguous arena still
fails; six separate prefilled CMA MM2S buffers plus the 24 MiB S2MM buffer
succeed, which is what produces `send_buffer_mode=all-cma` and
`median_copy_flush_us=0.00`.

## Exactness

Validation uses real encrypted OpenFHE BGVRNS ciphertexts and evaluation keys.
The probe establishes each boundary independently:

1. OpenFHE `EvalMultNoRelin` produces three evaluation-domain components.
2. `KeySwitchCore` exactly equals `KeySwitchPrecomputeCore` followed by
   `EvalFastKeySwitchCore`.
3. Manual additions of the key-switch outputs into `c0` and `c1` exactly equal
   OpenFHE `EvalMult`.
4. The FPGA result is compared coefficient by coefficient against those exact
   OpenFHE relinearized outputs.

The B64 milestone checks `12 towers x 4096 coefficients x 64 ciphertexts x 2
output components = 6,291,456` exact residue comparisons. All passed.

## Performance progression

| Checkpoint | Latency | Throughput |
| --- | ---: | ---: |
| Coefficient-domain FPGA bridge | `5951.00 us/ct` | `168.04 ct/s` |
| Evaluation-domain `EvalMultNoRelin`, single-clock B32 | `1200.56 us/ct` | `832.95 ct/s` |
| Evaluation-domain all-pair `EvalMultNoRelin`, B64 | `998.50 us/ct` | `1001.51 ct/s` |
| First fused BV protocol, repeated keys B8 | `10944.06 us/ct` | `91.37 ct/s` |
| Coefficient-major serialized B64 | `4685.22 us/ct` | `213.44 ct/s` |
| Ping-pong coefficient-major B64 | `4196.49 us/ct` | `238.29 ct/s` |
| Compute-drain overlap B64 | `4158.25 us/ct` | `240.49 ct/s` |
| Persistent output, no-copy B64 | **`4071.50 us/ct`** | **`245.61 ct/s`** |

The `EvalMultNoRelin` line remains the high-throughput path when a
three-component unrelinearized ciphertext is acceptable — it is roughly 4x
faster because it skips key switching entirely. The current front line targets
exact fused BV relinearization.

## Quick start

### 1. Simulate (no hardware required)

Icarus Verilog only:

```bash
./scripts/run_sim_regression.sh --quick
./scripts/sim/run_bv_keyreuse_multi_pair_session_sim.sh
```

### 2. Build the OpenFHE probe and vectors

Targets OpenFHE 1.5.1. Exports encrypted inputs, BV decomposition digits,
evaluation-key towers, key-switch references, and final relinearized components.

```bash
cd openfhe_eval_domain_bridge
OPENFHE_PREFIX=$HOME/.local/openfhe-1.5.1 ./build.sh
cd ..
```

This produces `openfhe_eval_domain_bridge` and `openfhe_relinearization_probe`.

### 3. Build the PYNQ-Z2 overlay

Vivado 2024.1:

```bash
./scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.sh
```

Implementation Tcl:
[`scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.tcl`](scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.tcl).
Artifacts land in `deploy/bv_keyreuse_multi_pair_session_dma150/`.

Bitstreams and hardware handoffs are **not** committed (`.gitignore` excludes
`*.bit` and `*.hwh`), so this step requires a Vivado installation. Only the
routed reports and `build_summary.txt` are in the repository.

### 4. Configure CMA

Create `/boot/uEnv.txt` with the boot arguments above and reboot:

```bash
grep -E 'CmaTotal|CmaFree' /proc/meminfo
cat /proc/cmdline
```

### 5. Install and run

```bash
./scripts/board/install/install_bv_keyreuse_multi_pair_session_board.sh
```

Then on the PYNQ-Z2:

```bash
sudo -i
REMOTE=/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session
"$REMOTE/run_bv_keyreuse_multi_pair_session_board.sh" "$REMOTE" 64 5 \
  | tee "$REMOTE/results/batch_64_all_cma.log"
```

A successful no-copy run reports:

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
| `rtl/` | modular arithmetic cores, coefficient-major schedulers, AXI4-Stream wrappers |
| `tests/rtl/` | Icarus testbenches for the evaluation-domain line |
| `tests/board/` | on-board DMA regression scripts |
| `tests/generated/` | exact OpenFHE-derived vector sets per checkpoint |
| `scripts/sim/` | RTL checkpoint launchers |
| `scripts/vivado/` | out-of-context timing sweeps and complete overlay builds |
| `openfhe_eval_domain_bridge/` | OpenFHE probe, vector exporter, validators, board runners |
| `deploy/` | routed reports, `build_summary.txt`, deployment metadata |
| `docs/` | architecture notes and historical checkpoint documentation |
| `reports/` | timing and utilization from development checkpoints |
| `model/` | Python golden models and NTT-stage references |

## Development lineage

| Name | Meaning |
| --- | --- |
| `poly_mul16`, `poly_mul256`, `poly_mul4096` | early polynomial-multiplication proofs of concept |
| `runtime_profile` | runtime-loadable modulus and NTT profiles |
| `two_tower_parallel` | two RNS towers packed into one 64-bit stream |
| `dual_butterfly`, `four_butterfly` | coefficient-domain NTT development lines |
| `evalmul3` | fused evaluation-domain three-component ciphertext product |
| `evalmul3_allpairs` | cached six-pair profiles, one logical unrelinearized batch |
| `bv_keyswitch_mac` | exact two-tower BV key-switch accumulation |
| `evalmul3_bv_relinearize` | connected exact multiplication and BV relinearization |
| `bv_keyreuse_coefficient_major` | evaluation-key reuse across a ciphertext batch |
| `bv_keyreuse_pingpong` | overlapping coefficient input and output banks |
| `bv_keyreuse_drain_overlap` | overlapping next coefficient with prior-bank compute drain |
| `bv_keyreuse_multi_pair_session` | one persistent output session across all six Q-tower pairs |

The coefficient-domain implementations remain useful as complete NTT-based
`DCRTPoly` references. The current design specializes for the representation
OpenFHE actually uses during ciphertext multiplication and concentrates the DSP
budget on exact modular products and BV key switching.

## Known limitations

- **Host-decomposed BV digits.** The FPGA does not compute BV CRT
  decomposition; digits are supplied by the host. A production path must either
  return `c2` and key-switch in a second FPGA pass, or implement CRT
  decomposition in RTL.
- **The OpenFHE reference timing is single-shot.** See the caveat under the
  headline result.
- **Runtime profiles are not validated in hardware.** Barrett preconditions are
  checked only under simulation.
- **`SYNTHESIS` is defined inconsistently** across build scripts, so
  simulation-only assertion blocks reach synthesis in most overlay builds.
- **CI covers only the coefficient-domain line.** `scripts/run_sim_regression.sh`
  globs `rtl/tb_*.sv`; the testbenches under `tests/rtl/` are not run
  automatically.
- **Top-level file sprawl.** Per-checkpoint `README_*`/`RESULTS_*` notes and
  build scripts accumulate at the repository root rather than under `docs/` and
  `scripts/`.

## License

MIT — see [`LICENSE`](LICENSE).
