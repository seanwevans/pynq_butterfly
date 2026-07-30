# Historical lineage

These notes preserve transitions and are not current build instructions. Follow
the lineage by subsystem:

- **NTT and polynomial pipeline:** begin with
  [`readme-shared-ab-pipeline.md`](readme-shared-ab-pipeline.md), then the
  four-butterfly memory, buffering, and two-tower notes.
- **Evaluation-domain multiplication:** the `readme-evalmul3-*` records cover the
  fused core, DMA integration, batch scaling, all-pair transport, and releases.
- **BV relinearization:** the `readme-bv-keyswitch-*` and
  `readme-evalmul3-bv-relinearized-*` records lead from standalone key-switch MAC
  work to the fused implementation.
- **Evaluation-key reuse:** the `readme-bv-keyreuse-*` records lead through
  coefficient-major, ping-pong, drain-overlap, and persistent multi-pair sessions.
- **OpenFHE integration:** the `readme-openfhe-*` records preserve packing,
  modulus, format, probe, and result-retrieval investigations.
- **Diagnostics and recovery:** `dsp-diagnosis.md`, `timing-diagnosis.md`, and
  files ending in `-fix.md` document superseded corrective work.

Measured evidence was separated from transition notes and is indexed by the
current [benchmark summary](../results/benchmark-summary.md).
