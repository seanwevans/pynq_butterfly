# Repository artifact inventory

> Scope: `reports/`, `deploy/`, `model/golden/`, `model/golden_n4096/`, `vivado/`, `board_db2b/`, and `board_db2b_sweep/` as inventoried on 2026-07-30.

## Classification policy

- **Source input**: hand-maintained code or constraints consumed to build, deploy, or validate the design.
- **Deterministic test fixture**: versioned data with stable expected contents used to drive or check a repeatable test.
- **Release artifact**: intentionally retained output that documents or accompanies a build/release, including reports, summaries, and manifests.
- **Disposable build output**: regenerable intermediate output that need not be retained. No file in the requested, Git-tracked scope currently falls in this class; transient Vivado project/cache/run products are kept outside these curated paths.

Classification describes the repository role of each file, not whether its bytes were generated. For example, a generated golden vector is a fixture because tests consume it, while a checked-in timing report is a release artifact because it preserves build evidence. All 275 files below are Git-tracked.

**Overall:** 37 source inputs, 95 deterministic test fixtures, 143 release artifacts, and 0 disposable build outputs.

## `reports/`

**113 files** (Release artifact: 113).

| File | Classification | Basis |
|---|---|---|
| `reports/modmul_barrett60_pipeline/dsp_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_barrett60_pipeline/synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_barrett60_pipeline_chunked/dsp_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_barrett60_pipeline_chunked/synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_barrett60_pipeline_split/dsp_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_barrett60_pipeline_split/synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_barrett60_pipeline_split_implemented/implementation_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_compare/baseline_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_compare/baseline_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_compare/modmul_radix4_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_compare/radix4_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_compare/radix4_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_flat_compare/baseline_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_flat_compare/baseline_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_flat_compare/modmul_radix4_flat_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_flat_compare/radix4_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/modmul_radix4_flat_compare/radix4_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_synth/ntt4096_dual_butterfly_cyclic_bram_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_synth/ntt4096_dual_butterfly_cyclic_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_synth/ntt4096_dual_butterfly_cyclic_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_synth/ntt4096_dual_butterfly_cyclic_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_synth/ntt4096_dual_butterfly_cyclic_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_xpm_synth/ntt4096_dual_butterfly_cyclic_xpm_bram_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_xpm_synth/ntt4096_dual_butterfly_cyclic_xpm_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_xpm_synth/ntt4096_dual_butterfly_cyclic_xpm_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_xpm_synth/ntt4096_dual_butterfly_cyclic_xpm_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_dual_butterfly_cyclic_xpm_synth/ntt4096_dual_butterfly_cyclic_xpm_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_bank_coeff_store_bram_synth/ntt4096_four_bank_coeff_store_bram_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_bank_coeff_store_bram_synth/ntt4096_four_bank_coeff_store_bram_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_bank_coeff_store_bram_synth/ntt4096_four_bank_coeff_store_bram_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_bank_coeff_store_bram_synth/ntt4096_four_bank_coeff_store_bram_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_bank_coeff_store_synth/ntt4096_four_bank_coeff_store_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_bank_coeff_store_synth/ntt4096_four_bank_coeff_store_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_bank_coeff_store_synth/ntt4096_four_bank_coeff_store_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_bank_coeff_store_synth/ntt4096_four_bank_coeff_store_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_butterfly_memory_checkpoint/synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_butterfly_pipeline_implemented/implementation_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/ntt4096_four_butterfly_transform_in_memory/synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul256/poly_mul256_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul256/poly_mul256_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul256/poly_mul256_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul256_axis/poly_mul256_axis_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul256_axis/poly_mul256_axis_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul256_axis_batch/poly_mul256_axis_batch_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul256_axis_batch/poly_mul256_axis_batch_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_axis_synth/poly_mul4096_axis_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_axis_synth/poly_mul4096_axis_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_axis_synth/poly_mul4096_axis_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_axis_synth/poly_mul4096_axis_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dma/poly_mul4096_dma_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dma/poly_mul4096_dma_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_runtime_synth/poly_mul4096_dual_butterfly_runtime_bram_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_runtime_synth/poly_mul4096_dual_butterfly_runtime_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_runtime_synth/poly_mul4096_dual_butterfly_runtime_modmul_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_runtime_synth/poly_mul4096_dual_butterfly_runtime_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_runtime_synth/poly_mul4096_dual_butterfly_runtime_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_runtime_synth/poly_mul4096_dual_butterfly_runtime_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_timing_isolated_in_memory/bram_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_timing_isolated_in_memory/hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_timing_isolated_in_memory/synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_timing_isolated_in_memory/timing_summary.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_timing_isolated_in_memory/utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_axis_synth/poly_mul4096_dual_butterfly_two_tower_axis_bram_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_axis_synth/poly_mul4096_dual_butterfly_two_tower_axis_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_axis_synth/poly_mul4096_dual_butterfly_two_tower_axis_modmul_cells.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_axis_synth/poly_mul4096_dual_butterfly_two_tower_axis_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_axis_synth/poly_mul4096_dual_butterfly_two_tower_axis_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_axis_synth/poly_mul4096_dual_butterfly_two_tower_axis_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_dma/poly_mul4096_dual_butterfly_two_tower_dma_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_dma/poly_mul4096_dual_butterfly_two_tower_dma_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_dma_timing_isolated/timing_summary.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_dma_timing_isolated/utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_dma_timing_recovery/timing_recovery_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_dma_timing_recovery/timing_summary.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_dual_butterfly_two_tower_dma_timing_recovery/utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_axis_synth/poly_mul4096_runtime_profile_axis_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_axis_synth/poly_mul4096_runtime_profile_axis_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_axis_synth/poly_mul4096_runtime_profile_axis_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_axis_synth/poly_mul4096_runtime_profile_axis_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_dma/poly_mul4096_runtime_profile_dma_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_dma/poly_mul4096_runtime_profile_dma_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_synth/poly_mul4096_runtime_profile_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_synth/poly_mul4096_runtime_profile_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_synth/poly_mul4096_runtime_profile_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_runtime_profile_synth/poly_mul4096_runtime_profile_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_synth/poly_mul4096_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_synth/poly_mul4096_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_synth/poly_mul4096_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_synth/poly_mul4096_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_axis_synth/poly_mul4096_two_bank_axis_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_axis_synth/poly_mul4096_two_bank_axis_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_axis_synth/poly_mul4096_two_bank_axis_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_axis_synth/poly_mul4096_two_bank_axis_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_dma/poly_mul4096_two_bank_dma_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_dma/poly_mul4096_two_bank_dma_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_synth/poly_mul4096_two_bank_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_synth/poly_mul4096_two_bank_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_synth/poly_mul4096_two_bank_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_bank_synth/poly_mul4096_two_bank_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_tower_parallel_dma/poly_mul4096_two_tower_parallel_dma_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_tower_parallel_dma/poly_mul4096_two_tower_parallel_dma_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_tower_parallel_synth/poly_mul4096_two_tower_parallel_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_tower_parallel_synth/poly_mul4096_two_tower_parallel_synthesis_summary.txt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_tower_parallel_synth/poly_mul4096_two_tower_parallel_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/poly_mul4096_two_tower_parallel_synth/poly_mul4096_two_tower_parallel_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/pynq_poly_mul256/pynq_poly_mul256_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/pynq_poly_mul256/pynq_poly_mul256_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/pynq_poly_mul256_dma/pynq_poly_mul256_dma_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/pynq_poly_mul256_dma/pynq_poly_mul256_dma_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/pynq_poly_mul256_dma/pynq_poly_mul256_dma_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/pynq_poly_mul256_dma_batch32/pynq_poly_mul256_dma_batch32_hierarchical_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/pynq_poly_mul256_dma_batch32/pynq_poly_mul256_dma_batch32_timing.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |
| `reports/pynq_poly_mul256_dma_batch32/pynq_poly_mul256_dma_batch32_utilization.rpt` | Release artifact | Curated synthesis/implementation evidence retained for comparison or review. |

## `deploy/`

**55 files** (Deterministic test fixture: 12, Release artifact: 30, Source input: 13).

| File | Classification | Basis |
|---|---|---|
| `deploy/bv_keyreuse_coefficient_major_dma150/build_summary.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/bv_keyreuse_drain_overlap_dma150/build_summary.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/bv_keyreuse_multi_pair_session_dma150/build_summary.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/bv_keyreuse_pingpong_dma150/build_summary.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_allpairs_dma150/build_summary.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_allpairs_dma150/routed_timing_summary.rpt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_allpairs_dma150/routed_utilization.rpt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_allpairs_dma150/run_fpga_evalmul3_allpairs.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/evalmul3_bv_relinearized_dma150/build_summary.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_bv_relinearized_dma150/routed_timing_summary.rpt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_bv_relinearized_dma150/routed_utilization.rpt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_two_tower_dma/build_summary.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_two_tower_dma/routed_timing_summary.rpt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_two_tower_dma/routed_utilization.rpt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_two_tower_dma/run_fpga_evalmul3.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/evalmul3_two_tower_dma150/build_summary.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_two_tower_dma150/routed_timing_summary.rpt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_two_tower_dma150/routed_utilization.rpt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/evalmul3_two_tower_dma150/run_fpga_evalmul3.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/n256_convolution.mem` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/n256_input_a.mem` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/n256_input_b.mem` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/poly_mul4096_dual_butterfly_two_tower_batch_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/poly_mul4096_dual_butterfly_two_tower_buffered_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/poly_mul4096_dual_butterfly_two_tower_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/poly_mul4096_dual_butterfly_two_tower_prefetch_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/poly_mul4096_four_butterfly_two_tower_batch_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/poly_mul4096_four_butterfly_two_tower_batch_dma/run_poly_mul4096_four_butterfly_two_tower_batch_board.sh` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/poly_mul4096_four_butterfly_two_tower_batch_dma/test_poly_mul4096_four_butterfly_two_tower_batch_dma.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/poly_mul4096_four_butterfly_two_tower_batch_dma/vectors/metadata.json` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_four_butterfly_two_tower_batch_dma/vectors/profile0/profile.json` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_four_butterfly_two_tower_batch_dma/vectors/profile1/profile.json` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_four_butterfly_two_tower_buffered_dma/run_poly_mul4096_four_butterfly_two_tower_buffered_board.sh` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/poly_mul4096_four_butterfly_two_tower_buffered_dma/test_poly_mul4096_four_butterfly_two_tower_buffered_dma.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/poly_mul4096_four_butterfly_two_tower_buffered_dma/vectors/metadata.json` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_four_butterfly_two_tower_buffered_dma/vectors/profile0/profile.json` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_four_butterfly_two_tower_buffered_dma/vectors/profile1/profile.json` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_four_butterfly_two_tower_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/poly_mul4096_four_butterfly_two_tower_dma/run_poly_mul4096_four_butterfly_two_tower_board.sh` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/poly_mul4096_four_butterfly_two_tower_dma/test_poly_mul4096_four_butterfly_two_tower_dma.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/poly_mul4096_four_butterfly_two_tower_dma/vectors/metadata.json` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_four_butterfly_two_tower_dma/vectors/profile0/profile.json` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_four_butterfly_two_tower_dma/vectors/profile1/profile.json` | Deterministic test fixture | Versioned input/profile data consumed by a repeatable board test. |
| `deploy/poly_mul4096_runtime_profile_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/poly_mul4096_two_bank_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/poly_mul4096_two_tower_parallel_dma/manifest.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/pynq_poly_mul16.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/pynq_poly_mul256.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/pynq_poly_mul256_dma.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/pynq_poly_mul256_dma_batch32.txt` | Release artifact | Curated deployment manifest or implementation/build report describing a produced overlay. |
| `deploy/test_poly_mul16.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/test_poly_mul256.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/test_poly_mul256_dma.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |
| `deploy/test_poly_mul256_dma_batch32.py` | Source input | Board-side test, runner, or orchestration code consumed during deployment validation. |

## `model/golden/`

**26 files** (Deterministic test fixture: 26).

| File | Classification | Basis |
|---|---|---|
| `model/golden/convolution.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_a.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_a_bit_reversed_input.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_a_stage0.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_a_stage1.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_a_stage2.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_a_stage3.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_b.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_b_bit_reversed_input.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_b_stage0.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_b_stage1.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_b_stage2.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_b_stage3.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/forward_schedule.csv` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/input_a.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/input_b.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/inverse_product_bit_reversed_input.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/inverse_product_stage0.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/inverse_product_stage1.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/inverse_product_stage2.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/inverse_product_stage3.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/inverse_schedule.csv` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/openfhe_tower0_n16_golden.json` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/pointwise.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/twisted_a.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden/twisted_b.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |

## `model/golden_n4096/`

**57 files** (Deterministic test fixture: 57).

| File | Classification | Basis |
|---|---|---|
| `model/golden_n4096/bit_reverse.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/butterfly_schedule.csv` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/convolution.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_bit_reversed.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage0.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage1.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage10.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage11.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage2.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage3.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage4.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage5.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage6.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage7.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage8.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_stage9.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_a_twisted_natural.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_bit_reversed.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage0.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage1.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage10.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage11.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage2.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage3.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage4.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage5.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage6.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage7.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage8.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_stage9.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_b_twisted_natural.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/forward_twiddles.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/input_a.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/input_b.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_bit_reversed.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_cyclic.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage0.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage1.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage10.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage11.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage2.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage3.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage4.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage5.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage6.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage7.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage8.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_product_stage9.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_scale_factors.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/inverse_twiddles.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/ntt4096_profile_pkg.sv` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/pointwise.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/profile.json` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/summary.txt` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |
| `model/golden_n4096/twist_factors.mem` | Deterministic test fixture | Versioned golden vector, schedule, profile, or generated reference collateral used to reproduce/check model and RTL behavior. |

## `vivado/`

**21 files** (Source input: 21).

| File | Classification | Basis |
|---|---|---|
| `vivado/modmul_radix4_compare/baseline/baseline.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/modmul_radix4_compare/radix4/radix4.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/modmul_radix4_flat_compare/baseline/baseline.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/modmul_radix4_flat_compare/radix4/radix4.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/ntt4096_dual_butterfly_cyclic_synth/ntt4096_dual_butterfly_cyclic_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/ntt4096_dual_butterfly_cyclic_xpm_synth/ntt4096_dual_butterfly_cyclic_xpm_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/ntt4096_four_bank_coeff_store_bram_synth/ntt4096_four_bank_coeff_store_bram_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/ntt4096_four_bank_coeff_store_synth/ntt4096_four_bank_coeff_store_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/package_poly_mul256/poly_mul256_clock.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/package_poly_mul256_axis/poly_mul256_axis_clock.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/package_poly_mul256_axis_batch/poly_mul256_axis_batch_clock.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_axis_synth/poly_mul4096_axis_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_dual_butterfly_runtime_synth/poly_mul4096_dual_butterfly_runtime_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_dual_butterfly_two_tower_axis_synth/poly_mul4096_dual_butterfly_two_tower_axis_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_dual_butterfly_two_tower_axis_timing_isolated_synth/poly_mul4096_dual_butterfly_two_tower_axis_timing_isolated_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_runtime_profile_axis_synth/poly_mul4096_runtime_profile_axis_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_runtime_profile_synth/poly_mul4096_runtime_profile_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_synth/poly_mul4096_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_two_bank_axis_synth/poly_mul4096_two_bank_axis_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_two_bank_synth/poly_mul4096_two_bank_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |
| `vivado/poly_mul4096_two_tower_parallel_synth/poly_mul4096_two_tower_parallel_synth.xdc` | Source input | Hand-authored Vivado timing constraint consumed by a build. |

## `board_db2b/`

**1 files** (Source input: 1).

| File | Classification | Basis |
|---|---|---|
| `board_db2b/test_db2b_openfhe_batch2_dma.py` | Source input | Board test or orchestration code consumed to run validation. |

## `board_db2b_sweep/`

**2 files** (Source input: 2).

| File | Classification | Basis |
|---|---|---|
| `board_db2b_sweep/run_board_batch_sweep.sh` | Source input | Board test or orchestration code consumed to run validation. |
| `board_db2b_sweep/test_db2b_openfhe_batch_sweep_dma.py` | Source input | Board test or orchestration code consumed to run validation. |

