# Release checkpoint

Copy these two files into the repository root, then commit and publish the
proven fused evaluation-domain accelerator:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_833pps_release_checkpoint.zip

./commit_evalmul3_833pps.sh --push
```

The helper stages an explicit allowlist. It does not add ZIP files, generated
OpenFHE vectors, Vivado working directories, or board result directories.

Release identity:

```text
branch  eval-domain-ciphertext-fused
tag     pynq-z2-evalmul3-833pps
```
