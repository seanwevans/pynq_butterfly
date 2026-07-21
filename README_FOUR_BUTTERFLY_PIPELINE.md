# NTT4096 four-butterfly pipelined integration

This checkpoint replaces the serialized `start/busy/done` butterfly group
with four continuously accepting butterfly lanes.

Target architecture:

- N: 4096
- stages: 12
- groups per stage: 512
- butterflies per group: 4
- multiplier latency: 7
- butterfly latency: 9
- initiation interval: 1 group per clock
- stage cycles: 523
- transform cycles: 6276
- iterative baseline: 141313 cycles

The stage controller drains the pipeline before advancing to the next NTT
stage. Groups within one stage are disjoint, so read issue and delayed
writeback safely overlap.

## Install from WSL

Place the ZIP in the repository root, then:

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./ntt4096_four_butterfly_pipeline_integration.zip
```

This drop adds new, uniquely named integration files. It does not replace the
iterative transform. It expects the already validated file:

```text
rtl/modmul_barrett60_pipeline_split_core.sv
```

It also expects the existing generated vectors under:

```text
rtl/generated_four_butterfly_ntt/
```

## Functional gate

```bash
./compile_ntt4096_four_butterfly_pipeline.sh
```

Expected final line:

```text
PASS: 4 pipelined transforms, 16384 checked coefficients, 6276 cycles each
```

## Routed implementation

```bash
./implement_ntt4096_four_butterfly_pipeline.sh
./check_ntt4096_four_butterfly_pipeline.py
```

## Complete sequence

```bash
./run_ntt4096_four_butterfly_pipeline_all.sh
```

The Vivado runner invokes `vivado` directly from WSL. The Tcl script derives
the repository root from its own location using `[info script]`.
