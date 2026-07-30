# Exact fused simulation result

```text
PASS: exact fused EvalMul3 + BV arithmetic reproduces OpenFHE relinearized ciphertext components
pair_count=6
digits=12
coefficient_count=32
profile_words=12
payload_words=7680
expected_words=384

PASS: exact fused EvalMul3 plus BV relinearization across all six tower pairs
PASS: exact fused OpenFHE BV relinearization RTL checkpoint complete
```

The final RTL output equals OpenFHE's relinearized `c0` and `c1` components
exactly. BV decomposition remains host-side; all dense modular multiplication,
accumulation, and final component addition are in the fused RTL.
