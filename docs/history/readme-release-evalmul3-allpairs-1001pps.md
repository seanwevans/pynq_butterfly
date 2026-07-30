# Release helper

Apply this checkpoint on the completed `evalmul3-all-pair-frame` branch:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o   evalmul3_allpairs_1001pps_release_checkpoint.zip

./scripts/archive/commit_evalmul3_allpairs_1001pps.sh --push
```

The helper stages only the explicit all-pair source, documentation, and
`deploy/evalmul3_allpairs_dma150` allowlist. It does not stage unrelated
untracked files.

Release identity:

```text
branch:  evalmul3-all-pair-frame
tag:     pynq-z2-evalmul3-allpairs-1001pps
message: perf: exceed 1000 exact EvalMultNoRelin per second at batch 64
```
