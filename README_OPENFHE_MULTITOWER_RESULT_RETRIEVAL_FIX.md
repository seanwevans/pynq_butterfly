# Multi-tower result retrieval fix

The FPGA run completed successfully. The failure occurred afterward in:

```bash
scp -r host:/remote/results/. local/
```

Recent OpenSSH `scp` implementations may reject the final remote filename `.` with:

```text
error: unexpected filename: .
```

This patch replaces that copy with a binary-safe tar stream over SSH.

Apply:

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o openfhe_multitower_result_retrieval_fix.zip
cd openfhe_multitower_bridge
```

Recover and verify the already-completed six-tower run without rerunning the FPGA:

```bash
./recover_openfhe_multitower_results.sh 6 4
```

Future complete runs use the patched end-to-end script:

```bash
./run_openfhe_multitower_e2e.sh 5 4 2
./run_openfhe_multitower_e2e.sh 12 32 3
```
