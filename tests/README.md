# Test layout and prerequisites

Test sources have one canonical home:

- `rtl/` contains synthesizable production RTL; SystemVerilog testbenches live in `tests/rtl/`.
- `tests/host/` contains host-only Python tests.
- `tests/board/` contains tests that execute against a PYNQ overlay.
- `tests/support/` is an importable, test-only package for expected-value,
  timing-report, and protocol checkers. Production vector generators remain in
  `scripts/vectors/` and host runtime code remains outside `tests/`.

Run an explicit suite through the dispatcher:

```console
./scripts/run_tests.sh fast
./scripts/run_tests.sh rtl
./scripts/run_tests.sh host
PYNQ_BOARD_TESTS=1 ./scripts/run_tests.sh board
```

The board suite is never selected by `fast`, `rtl`, `host`, CI, or the aggregate
simulation command. `scripts/run_sim_regression.sh` is the documented aggregate
static/simulation entry point. It reports unavailable simulator tools and
missing optional vectors as `SKIP`, separately from `FAIL`.

## Software prerequisites

- Bash, Python 3, and `pytest` (for Python suites).
- Icarus Verilog (`iverilog` and `vvp`) for RTL simulation. If absent, the
  aggregate command runs static shell checks and reports simulation as skipped.
- GNU coreutils `timeout` for `SIM_TEST_TIMEOUT` (default 1800 seconds per test).
- Vivado only for synthesis/implementation launchers, not ordinary suites.

## Generated fixtures

Committed evaluation-domain fixtures are under `tests/generated/`. Their
`metadata.json`, `payload.hex`, `profiles.hex`, and `expected.hex` files are
consumed through `+VECTOR_ROOT`. Buffered4 and prefetch4 vectors are intentionally
not committed. Generate them with
`scripts/vectors/prepare_dual_butterfly_prefetch4_vectors.py`; OpenFHE-derived
fixtures require a built OpenFHE bridge and its dependencies. Missing optional
fixture sets are skips, not failures.

## Board requirements

Board tests require the target PYNQ Linux environment, the `pynq` Python package,
DMA allocator access, and matching `.bit` and `.hwh` overlays installed at the
paths expected by each test. Prepare overlays with `scripts/board/install/`.
Set `PYNQ_BOARD_TESTS=1` only after satisfying these requirements; the opt-in
prevents accidental hardware access on developer and CI hosts.
