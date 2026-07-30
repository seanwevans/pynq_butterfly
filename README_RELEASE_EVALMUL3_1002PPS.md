# 1K EvalMultNoRelin release checkpoint

This release freezes the first exact PYNQ-Z2 result above 1,000 encrypted
OpenFHE `EvalMultNoRelin` operations per second.

Apply, commit, tag, and push:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_1002pps_release_checkpoint.zip

./scripts/archive/commit_evalmul3_1002pps.sh --push
```

Release identity:

```text
branch  evalmul3-dma-throughput
tag     pynq-z2-evalmul3-1002pps
```

The helper stages an explicit allowlist. Old experiments, generated vectors,
ZIP files, and board result directories remain untracked.

The included board installer no longer attempts to delete root-owned benchmark
results when refreshing vectors.
