# OpenFHE Format namespace fix

OpenFHE 1.5.1 exposes `Format` in the global namespace, not as
`lbcrypto::Format`.

The failed line was:

```cpp
using lbcrypto::Format;
```

The probe already refers to `Format::EVALUATION`, which resolves correctly
after removing that invalid using-declaration.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o   openfhe_relinearization_format_namespace_fix.zip

./run_openfhe_relinearization_probe.sh
```

The clock-skew warnings from WSL are unrelated to this compile error.
