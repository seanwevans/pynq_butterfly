# EvalMul3 + BV relinearization release checkpoint

This package consolidates the exact OpenFHE probe, final RTL, simulation,
physical overlay build, PYNQ runner, and measured board result.

## Commit

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_relinearized_91pps_release.zip

./scripts/archive/commit_evalmul3_bv_relinearized_91pps.sh --push
```

Commit:

```text
feat: run exact fused OpenFHE BV relinearization on PYNQ-Z2
```

Tag:

```text
pynq-z2-bv-relinearized-91pps
```

This is an exact execution checkpoint, not yet a throughput win. The current
frame retransmits the evaluation key for every ciphertext and is input-limited
at 101.725 operations/s.

The next transport architecture is documented in:

```text
NEXT_EVAL_KEY_REUSE_ARCHITECTURE.md
```
