# Pipelined NTT transform-read-valid fix

The coefficient store performs inspection reads continuously while the
transform is idle. The original integration connected its generic
`read_data_valid` directly to the butterfly lanes. That launched idle data
before the transform started, including before a modulus had been selected.

This replacement adds `transform_read_data_valid`, delayed one clock from
`STATE_ISSUE`, and launches a butterfly only when both valid signals agree.

The existing address delay and timing model remain unchanged:

- stage cycles: 523
- transform cycles: 6276
- butterfly pipeline latency: 9
- initiation interval: 1

Install from the repository root:

```bash
unzip -o ./ntt4096_four_butterfly_pipeline_valid_fix.zip
./compile_ntt4096_four_butterfly_pipeline.sh
```
