# Arithmetic architecture

The current accelerator consumes OpenFHE BGV ciphertext components in the
evaluation domain. For each coefficient and Q tower it computes the three
ciphertext products, then uses host-supplied BV CRT digits to accumulate the
evaluation-key products and return the two relinearized components.

The datapath uses ten initiation-interval-one Barrett pipelines: two for `c0`,
four for the `c1` cross-products, and two each for the evaluation-key `a` and
`b` products. The 32-bit residues require `0 < q < 2^30`; operands must be
reduced and `mu` is `floor(2^60 / q)`. See
[`modmul_barrett60_pipeline_split_core.sv`](../../rtl/modmul_barrett60_pipeline_split_core.sv)
for the seven-cycle implementation.

The architectural boundary and its rationale are detailed in
[`relinearization-boundary.md`](relinearization-boundary.md). Earlier arithmetic
experiments and fixes remain available through the [historical lineage](../README.md#historical-lineage).
