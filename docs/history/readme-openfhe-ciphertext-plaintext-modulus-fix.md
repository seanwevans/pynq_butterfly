# BGV plaintext-modulus compatibility fix

The first encrypted-ciphertext run failed during OpenFHE context generation:

```text
LastPrime(): overflow shrinking candidate
```

This was not an FPGA or ciphertext problem.

For BGV `FIXEDMANUAL`, OpenFHE requires each RNS modulus to be congruent to
one modulo both the cyclotomic order and the odd part of the plaintext
modulus. With the original settings:

```text
N                  = 4096
cyclotomic order   = 8192
plaintext modulus  = 65537
required order     = 8192 * 65537 = 536879104
Q limit            < 2^30 = 1073741824
```

Only one positive candidate of the form `k*536879104 + 1` fits below `2^30`,
namely `536879105`, and it is composite. `LastPrime()` therefore walks below
the valid range and reports the overflow.

The patch changes the plaintext modulus to the Fermat prime `257`. The test
messages already use values from 0 through 31, so this does not reduce the
current workload. It leaves many valid 29-bit primes below the hardware's
`2^30` limit.

A preflight guard was also added so incompatible future choices fail with a
direct explanation before OpenFHE enters `LastPrime()`.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  openfhe_ciphertext_plaintext_modulus_fix.zip

cd openfhe_ciphertext_bridge

./run_openfhe_ciphertext_e2e.sh 6 2 2
```
