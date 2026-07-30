# Artifact policy

This policy defines when generated files must be rebuilt, what evidence makes
them valid, how long they are kept, and when they may be promoted to a release.
It applies to simulation vectors and logs, Vivado projects and reports, hardware
exports, deployment bundles, board results, and benchmark records. Source RTL,
scripts, constraints, tests, and hand-written documentation are not artifacts.

The repository is the source of truth for source and durable evidence, not a
general-purpose build cache. A file being present under `deploy/`, `reports/`,
or a generated-vector directory does not by itself make that file releasable.

## Artifact classes and ownership

| Class | Examples | Default disposition |
| --- | --- | --- |
| Ephemeral build output | Vivado work directories, `.Xil/`, logs, journals, simulation executables, waveforms, generated IP, checkpoints | Regenerate locally; do not commit or release. |
| Reproducible generated output | `reports/`, `rtl/generated_*`, `tests/generated/`, board vector directories | Regenerate when an input changes. Keep only a deliberately selected, reviewed baseline. |
| Deployment output | matching `.bit` and `.hwh` files, optional `.xsa`, runner/install scripts, manifest, timing and utilization summaries under `deploy/` | Retain together as a versioned bundle outside Git; promote only after all release gates pass. |
| Durable evidence | `docs/results/` records and the benchmark summary | Commit when the measurement is accepted and sufficiently described to reproduce and interpret it. |
| Historical evidence | superseded investigations, checkpoint notes, and release notes under `docs/history/` | Retain for lineage; never treat as a current procedure or release candidate. |

The person producing an artifact owns its provenance and validation record. The
reviewer approving promotion must be able to trace every deployed file and
reported number to one source revision and one build invocation.

## Regeneration rules

Regenerate an artifact whenever an input that can affect it changes. Inputs
include RTL, constraints, block-design or packaging Tcl, vector generators,
testbench/checker code, software dependencies, board files, tool versions,
build options, clock or part selection, and input data or random seeds. Rebuild
the complete dependent bundle; do not combine a new bitstream with an old
hardware handoff, manifest, report, runner, or result record.

Use the maintained command that owns the artifact. For the supported overlay,
run:

```bash
scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.sh
```

The launcher removes its work directory and named deployment outputs before
building, so a reported success cannot be satisfied by stale files. Other
producers must provide the same clean-build property. Delete ignored output or
use a fresh work directory before regeneration; never rely on timestamps alone.

Record, alongside a candidate bundle or in its result document:

- the full Git commit ID and whether the source tree was clean;
- the exact producer command and relevant non-default arguments/environment;
- tool, board-file, simulator, and external-library versions;
- target board/part, clocks, and any vector seed or dataset identifier;
- UTC build and validation times, builder identity, and machine/board identity;
- the manifest/build summary and SHA-256 digest of every released file.

Absolute paths emitted by current manifests are diagnostic only. They must not
be used as artifact identity or as proof that two bundles have the same inputs.
If reproducibility is being assessed, repeat the build from a clean checkout.
Binary equality is desirable but is not required when a tool embeds timestamps;
in that case compare the declared inputs and the validated functional and
implementation results, and document the nondeterminism.

## Validation rules

Validation is fail-closed: a missing, skipped, timed-out, stale, or unreviewed
required check is not a pass. Preserve the command, exit status, and complete
output for each required check. A `PASS` marker is useful only when its producer
exited successfully and all required files were created during that invocation.

Apply the following gates in order:

1. **Source checks.** Start from the recorded clean revision, review the input
   diff, and run formatting or static checks applicable to changed scripts,
   RTL, software, and documentation.
2. **Functional simulation.** Run `scripts/run_sim_regression.sh --all` and any
   focused tests for the changed subsystem. Regenerate external vectors first
   when they are a required input; the regression's documented vector skips do
   not qualify a release candidate.
3. **Implementation.** Require successful synthesis, placement, routing, and
   bitstream generation for the intended part. The routed timing report must
   show no timing violations (including nonnegative WNS for required clocks),
   and DRC/build errors must be absent. Review utilization against device and
   project limits rather than accepting file existence alone.
4. **Bundle integrity.** Confirm that `.bit` and `.hwh` names match, the optional
   `.xsa` comes from the same run, the manifest describes the intended protocol,
   addresses, clocks, and frame sizes, and all recorded digests match. Run the
   installer's preflight checks where available.
5. **Board validation.** Install the exact digested bundle on the target PYNQ-Z2
   and run correctness tests with the release dataset. For performance claims,
   use the documented warm-up and sample method, retain raw output, and confirm
   the result is not a regression against the currently promoted baseline.
6. **Evidence review.** Add or update a `docs/results/` record with revision,
   commands, configuration, pass/fail criteria, measurements, and links or
   digests for retained output. Update `docs/results/benchmark-summary.md` only
   from accepted result records. A second person reviews the evidence before
   release promotion.

A waiver must name the omitted gate, explain why it is safe, identify the
approver, and have an expiry or follow-up issue. A waived candidate is marked
pre-release unless the release owner explicitly accepts the risk; functional
correctness, bundle matching, and artifact integrity cannot be waived.

## Retention rules

- Keep ephemeral output only until the producing job and immediate diagnosis
  finish. CI may expire successful logs and intermediate artifacts after 14
  days and failed-job diagnostics after 30 days.
- Keep unpromoted candidate bundles and their validation records for 30 days
  after the decision, then delete them unless an active investigation cites
  them.
- Keep every promoted deployment bundle, its checksums, manifest, reports, raw
  board output, validation record, and release decision for the lifetime of the
  release plus at least one year after it is superseded.
- Keep committed result and history documents indefinitely. Do not rewrite or
  delete old measurements merely because a newer result exists; mark the old
  release superseded and link to its successor.
- Keep only generated vectors needed to reproduce an accepted result or cover a
  maintained test. Record the generator revision, arguments, seed, dependency
  version, and checksum. Otherwise regenerate them on demand.

Large binaries, archives, Vivado projects, and ignored report trees must remain
in release/CI storage, not be force-added to Git. Repository exceptions must be
small, reviewable baselines whose absence would prevent ordinary validation;
the commit message and result record must explain the exception. Protect
retained release bundles from mutation. Access is by release identifier and
digest, and deletion follows the storage owner's audited retention process.

Never retain credentials, private keys, machine-specific secrets, licensed
tool payloads, or personal data in artifacts. Quarantine a bundle if prohibited
content is discovered, then replace it with a sanitized, newly digested bundle.

## Release promotion and rollback

Promotion moves an immutable candidate to a release channel; it does not rebuild
or edit it. Use this sequence:

1. Freeze a candidate from a clean, immutable Git commit and assign a unique
   release identifier. Upload the complete bundle and checksums to candidate
   storage.
2. Complete every validation gate against that exact bundle. Attach the
   validation record and reviewer approval to the release identifier.
3. Verify that supported documentation and install/run commands name the same
   interface and configuration. Record known limitations and compatibility
   requirements.
4. Promote by changing the channel pointer or publishing the already digested
   bundle atomically. Tag the source revision and publish release notes that
   identify the artifact digests and accepted result record.
5. Download through the release channel, verify the digests, and perform a
   smoke installation. Announce promotion only after this check passes.

Do not promote from a dirty tree, from an archival script, on the strength of
simulation alone, or by copying individual files between build runs. Failure of
any gate returns the candidate to development; keep its evidence according to
the candidate retention rule.

To roll back, repoint the release channel to the last validated immutable
bundle—never rebuild an old version—and repeat digest verification and the
smoke test. Preserve the withdrawn bundle, mark it withdrawn without deleting
or overwriting it, and add an incident or result note identifying the reason,
affected releases, and replacement. Fixes are regenerated and promoted as new
release identifiers.
