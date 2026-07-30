# Unified OpenFHE host tools

This project owns the reusable host library, all OpenFHE executables, Python
vector/board commands, and unit tests. The first refactor intentionally retains
every command's arguments and output format. Set `OPENFHE_PREFIX` when OpenFHE
is not installed in `$HOME/.local/openfhe-1.5.1`.

```sh
OPENFHE_PREFIX=/opt/openfhe scripts/host/build_openfhe_tools.sh
cmake -S host/openfhe -B host/openfhe/build-tests \
  -DPYNQ_OPENFHE_BUILD_TOOLS=OFF
cmake --build host/openfhe/build-tests && ctest --test-dir host/openfhe/build-tests
```

Python commands live in `host/openfhe/python/pynq_butterfly/cli`. For an
installed board checkout, set `PYTHONPATH=host/openfhe/python` and invoke them
with `python3 -m pynq_butterfly.cli.<command>`. The old bridge-local Python and
`build.sh` paths remain compatibility launchers.

## Command-to-target migration

| Former command/project | Unified CMake target or Python module |
|---|---|
| `openfhe_ciphertext_bridge/build/openfhe_ciphertext_bridge` | `openfhe_ciphertext_bridge` (ciphertext workflow) |
| `openfhe_eval_domain_bridge/build/openfhe_eval_domain_bridge` | `openfhe_eval_domain_bridge` (evaluation-domain workflow) |
| `openfhe_eval_domain_bridge/build/openfhe_relinearization_probe` | `openfhe_relinearization_probe` |
| `openfhe_multitower_bridge/build/openfhe_multitower_bridge` | `openfhe_multitower_bridge` (multitower workflow) |
| `openfhe_tower_bridge/build/openfhe_tower_bridge` | `openfhe_tower_bridge` (tower workflow) |
| `openfhe_two_tower_runtime_bridge/build/openfhe_two_tower_runtime_bridge` | `openfhe_two_tower_runtime_bridge` (two-tower runtime workflow) |
| `openfhe_*_bridge/run_*.py` | `python3 -m pynq_butterfly.cli.<basename>` |
| `openfhe_eval_domain_bridge/prepare_*.py` | `python3 -m pynq_butterfly.cli.<basename>` |
| Any bridge-local `./build.sh` | `scripts/host/build_openfhe_tools.sh` |

The `pynq_openfhe_host` library centralizes little-endian serialization, lane
packing/decoding, numeric parsing, and FPGA modulus validation. The
`pynq_butterfly.frames`, `profiles`, and `validation` modules are the matching
shared Python API; board code should import these rather than copying protocol
constants.
