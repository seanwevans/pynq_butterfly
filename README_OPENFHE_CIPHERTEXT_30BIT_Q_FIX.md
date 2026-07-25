# 30-bit Q-chain / Barrett reciprocal fix

The encrypted ciphertext vectors were generated successfully, but the board
runner rejected the first profile:

```text
reciprocal 2173082084 does not fit 31 bits
```

For the generated modulus:

```text
q  = 530546689
mu = floor(2^60 / q) = 2173082084
```

The multiplier's reciprocal field is 31 bits. Therefore `mu < 2^31`, which is
equivalent to:

```text
q > 2^29
```

Combined with the existing modulus restriction, the true hardware window is:

```text
2^29 < q < 2^30
```

The bridge requested **29-bit** OpenFHE primes, which necessarily put `q` below
`2^29`. The patch requests **30-bit** primes instead. A 30-bit prime is still
strictly below `2^30`; "30-bit" describes its bit length, not a value above the
hardware limit.

For `N=4096`, `t=257`, and BGV `FIXEDMANUAL`, there are many suitable primes in
this interval. The patch also adds a C++ preflight check so an undersized
modulus is rejected before files are copied to the board.

Apply and force a clean rebuild:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  openfhe_ciphertext_30bit_q_fix.zip

cd openfhe_ciphertext_bridge
rm -rf build

./run_openfhe_ciphertext_e2e.sh 6 2 2
```
