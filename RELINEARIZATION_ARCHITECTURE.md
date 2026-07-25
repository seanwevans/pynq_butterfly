# Relinearization architecture boundary

For a normal two-by-two ciphertext product, OpenFHE first produces three
components. It then key-switches only `c2`, adds the two returned polynomials
to `c0` and `c1`, and drops the third component.

The software probe splits this into measurable stages:

```text
Stage A: EvalMultNoRelin
    produces c0, c1, c2 in Q/evaluation form

Stage B: EvalKeySwitchPrecomputeCore(c2)
    produces technique-specific digits

Stage C: evaluation-key MAC
    BV:     EvalFastKeySwitchCore in Q
    HYBRID: EvalFastKeySwitchCoreExt in QP

Stage D: technique finalization
    BV:     none beyond the Q accumulation
    HYBRID: ApproxModDown from QP to Q

Stage E: final additions
    result0 = c0 + ks_b
    result1 = c1 + ks_a
```

The immediate hardware target is Stage C because it is a dense,
coefficient-wise modular multiply-accumulate and directly reuses the existing
Barrett pipelines. Stages B and D require basis conversion and NTT work and
should be implemented only after the exact technique dimensions are known.
