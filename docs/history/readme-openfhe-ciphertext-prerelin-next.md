# OpenFHE encrypted ciphertext pre-relinearization bridge

This checkpoint moves from synthetic `DCRTPoly` values to real encrypted
OpenFHE BGVRNS ciphertexts.

For each pair of two-component ciphertexts:

```text
A = (a0, a1)
B = (b0, b1)
```

the existing FPGA polynomial multiplier computes four arbitrary-tower products:

```text
p00 = a0 * b0
p01 = a0 * b1
p10 = a1 * b0
p11 = a1 * b1
```

The host reconstructs the exact three-component ciphertext produced by
`EvalMultNoRelin`:

```text
c0 = p00
c1 = p01 + p10
c2 = p11
```

The generator creates a real `CryptoContext`, key pair, packed plaintexts, and
encrypted ciphertexts. It calls OpenFHE `EvalMultNoRelin`, requires the
component convolution above to match exactly, then exports the four raw
products for the timing-closed PYNQ-Z2 overlay.

The final verifier independently recomputes every raw polynomial product,
imports the FPGA results, reconstructs `(c0,c1,c2)`, and compares all three
components exactly with the stored OpenFHE `EvalMultNoRelin` result.

## Hardware constraints

```text
scheme                  BGVRNS
ring dimension          4096
runtime Q primes        29 bits
hardware modulus limit  below 2^30
input components        2
output components       3
raw products/ciphertext 4
```

The context uses `HEStd_NotSet` with a forced ring dimension because this is an
integration benchmark for the existing fixed-N hardware, not a recommended
production security parameter set.

## Apply

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  openfhe_ciphertext_prerelin_bridge_checkpoint.zip

cd openfhe_ciphertext_bridge
```

## First compile and smoke test

Use six towers and two ciphertext products:

```bash
./run_openfhe_ciphertext_e2e.sh 6 2 2
```

Expected host-side generation includes:

```text
PASS: generated 2 pairs of real encrypted BGVRNS ciphertexts
PASS: every OpenFHE EvalMultNoRelin output has three components
PASS: component convolution is exact before export
```

Expected final verification includes:

```text
PASS: every FPGA raw component product equals OpenFHE
PASS: c0 = a0*b0 exactly
PASS: c1 = a0*b1 + a1*b0 exactly
PASS: c2 = a1*b1 exactly
PASS: every reconstructed three-component ciphertext equals OpenFHE EvalMultNoRelin component-wise
PASS: encrypted BGVRNS pre-relinearization bridge completed end to end
```

## Representative run

```bash
./run_openfhe_ciphertext_e2e.sh 12 16 3
```

A larger amortization run is:

```bash
./run_openfhe_ciphertext_e2e.sh 12 32 3
```

Arguments:

```text
TOWER_COUNT CIPHERTEXT_COUNT TIMED_RUNS [SEED]
```

## Performance counters

The board runner reports:

```text
compute_pre_relinearization_ciphertexts_per_second
end_to_end_pre_relinearization_ciphertexts_per_second
effective_raw_DCRTPoly_products_per_second
effective_tower_pair_products_per_second
```

One pre-relinearization ciphertext product requires four complete DCRTPoly
products, each spanning `ceil(tower_count/2)` FPGA tower pairs.

## Next boundary

After this exact checkpoint, the next implementation step is relinearization:
basis decomposition, key-switch products, accumulation, and return to a
two-component ciphertext. That step should reuse the same profile and
arbitrary-tower batching infrastructure rather than returning each
intermediate polynomial to Python.
