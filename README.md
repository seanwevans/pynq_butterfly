# pynq_butterfly

An FPGA accelerator for exact [OpenFHE](https://github.com/openfheorg/openfhe-development)
`DCRTPoly` polynomial multiplication in `Z_q[X] / (X^4096 + 1)`, running on a
PYNQ-Z2 (Zynq XC7Z020). The design grew from an N=16 proof of concept through
N=256 to the current two-tower N=4096 overlays, and every overlay is validated
bit-exactly against OpenFHE on real hardware.

## Headline result

The buffered-handoff overlay computes exact two-tower `DCRTPoly` products
end-to-end faster than the measured OpenFHE CPU reference on the host used for
comparison:

- 6,358.07 us median per product at batch 16 (157.3 products/s)
- 1.126x the measured OpenFHE CPU reference (7,161.35 us/product)
- 651 products validated on hardware: 5,332,992 coefficient comparisons, 0 mismatches
- 100 MHz PL clock, timing closed (WNS +0.179 ns), 0 DSP, 75 BRAM tiles

Physical median per product across the development line:

| Overlay | Median per product |
| --- | --- |
| parallel two-tower | 14,384.08 us |
| timing-isolated dual-butterfly | 7,186.59 us |
| batch-of-two | 6,865.63 us |
| arbitrary batch-16 | 6,515.42 us |
| operand-prefetch batch-16 | 6,425.53 us |
| buffered-handoff batch-16 | 6,358.07 us |

## Architecture

- Two RNS towers (`q0 = 1073692673`, `q1 = 1073668097`) execute in lockstep
  lanes behind one 64-bit AXI4-Stream DMA interface; lane 0 occupies bits
  31:0 of each stream word and lane 1 bits 63:32.
- Each tower runs two butterflies per cycle against four-bank coefficient
  stores; 24 radix-4 iterative modular-multiplier lanes total.
- NTT twiddle/twist/scale profiles are runtime-loaded, so one bitstream
  serves any 32-bit modulus profile.
- One prefetched operand pair and one buffered result polynomial per tower
  overlap DMA transfer with computation; the arithmetic core runs 631,810
  cycles per product with a 1,025-cycle handoff between batched products.

### On the zero-DSP arithmetic

Every shipped overlay computes modular products with LUT-only iterative
multipliers (two bits per cycle, 16 cycles per 32-bit product). This is a
deliberate trade: the iterative cores close timing comfortably at 100 MHz on
the XC7Z020 while leaving all 220 DSP48 slices free. A DSP-based pipelined
Barrett multiplier (`rtl/modmul_barrett60_pipeline_split_core.sv`, latency 7,
initiation interval 1) is under active development on the four-butterfly
line together with an eight-bank coefficient store; see
`docs/checkpoints/README_FOUR_BUTTERFLY_PIPELINE.md`.

## Variant glossary

| Name | Meaning |
| --- | --- |
| `poly_mul16`, `poly_mul256` | early proof-of-concept multipliers (AXI-Lite, then AXI-Stream) |
| `poly_mul4096` | first N=4096 multiplier, single butterfly |
| `two_bank` | two-bank coefficient store, DIF/DIT schedule |
| `runtime_profile` | runtime-loadable modulus/twiddle profiles |
| `two_tower_parallel` | two runtime-profile cores in lockstep RNS lanes |
| `dual_butterfly` | two butterflies per tower, four-bank stores, 631,810-cycle core |
| `db2ti` | short IP name: dual-butterfly two-tower, timing-isolated |
| `db2b` | + arbitrary-count batched products (`MULB` command) |
| `db2p` | + one-product operand prefetch |
| `db2r` | + buffered result handoff (current best overlay) |
| `four_butterfly` | in development: four butterfly lanes, eight banks, DSP Barrett multipliers |

## Repository layout

| Path | Contents |
| --- | --- |
| `rtl/` | all SystemVerilog sources and `tb_*.sv` testbenches (single source of truth) |
| `model/` | Python golden models and per-stage `.mem` vectors for N=16/256/4096 |
| `scripts/synth/` | synthesis/implementation studies (Vivado Tcl, WSL launchers) |
| `scripts/package/` | IP packaging Tcl (regenerates `ip/`, which is gitignored) |
| `scripts/integrate/` | PYNQ-Z2 overlay integration, timing recovery, inspection Tcl |
| `scripts/sim/` | Icarus compile drivers and simulation result checkers |
| `scripts/vectors/` | test-vector generators for the RTL testbenches |
| `scripts/run_sim_regression.sh` | full Icarus regression runner (CI entry point) |
| `tests/board/` | PYNQ board tests, sweep launchers, `overlay_constants.py` |
| `openfhe_tower_bridge/`, `openfhe_two_tower_runtime_bridge/` | C++ bridges that extract exact OpenFHE vectors and validate FPGA results |
| `deploy/` | per-overlay deployment manifests (bitstreams themselves are gitignored) |
| `reports/` | committed synthesis/implementation timing and utilization reports |
| `docs/` | milestone documents and `docs/checkpoints/` development notes |
| `profiles/` | OpenFHE tower profiles (moduli, roots) |
| `vivado/` | per-study constraint files |

## Simulation

Icarus Verilog drives all regressions (`apt install iverilog`):

    scripts/run_sim_regression.sh --quick    # unit tests, about a minute
    scripts/run_sim_regression.sh --all      # full suite, tens of minutes

The five dual-butterfly integration testbenches run with `-DFAST_MODMUL`
and the exact behavioral `modmul_core_fast_sim.sv` as documented in
`docs/checkpoints/README_FAST_SIM.md`. CI runs both tiers on every pull
request (`.github/workflows/sim-regression.yml`).

## Building an overlay

Each overlay follows the same Vivado flow (2024.1, from the repository
root; several scripts use Windows `F:/` working paths from the original
development machine — adjust to taste):

1. `scripts/package/package_<variant>_ip.tcl` — stages the RTL from `rtl/`
   and packages the IP.
2. `scripts/integrate/integrate_<variant>_dma.tcl` — builds the PYNQ-Z2
   DMA block design and writes the bitstream.
3. Copy the `.bit`/`.hwh` plus the matching `tests/board/` script,
   `tests/board/overlay_constants.py`, and vectors to the board; the
   `deploy/<overlay>/manifest.txt` files record what shipped in each
   overlay.

Board tests replay OpenFHE-extracted vectors through the DMA and compare
every coefficient against the OpenFHE expected product.

## License

MIT — see `LICENSE`.
