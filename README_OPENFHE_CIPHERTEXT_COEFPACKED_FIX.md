# Coefficient-packed plaintext fix

The `t=257` context now generates correctly. The new failure occurs later when
the bridge calls:

```cpp
context->MakePackedPlaintext(...)
```

SIMD packed encoding asks OpenFHE for an 8192nd root of unity modulo the
plaintext modulus. Since:

```text
257 - 1 = 256
```

`257` cannot contain an element of order `8192`, so OpenFHE correctly rejects:

```text
RootOfUnity(): primeModulus = 257 and m = 8192 do not satisfy (q-1)/m integer
```

Requiring SIMD packing and BGV `FIXEDMANUAL` simultaneously is incompatible
with the present hardware constraints:

- SIMD packing wants `t = 1 mod 8192`;
- FIXEDMANUAL chooses Q primes modulo `lcm(8192, t)`;
- the FPGA requires every Q prime below `2^30`;
- the bridge needs several distinct Q primes.

For this checkpoint, SIMD packing is unnecessary. We only need real encrypted
OpenFHE ciphertext components. The patch therefore changes:

```cpp
MakePackedPlaintext(...)
```

to:

```cpp
MakeCoefPackedPlaintext(...)
```

Coefficient-packed plaintexts remain real OpenFHE plaintexts and encrypt into
ordinary two-component BGVRNS ciphertexts, but they do not require an 8192nd
root of unity modulo `t`.

The test values remain `0..31`, so `t=257` is sufficient.

Apply and force a rebuild:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  openfhe_ciphertext_coefpacked_fix.zip

cd openfhe_ciphertext_bridge
rm -rf build

./run_openfhe_ciphertext_e2e.sh 6 2 2
```
