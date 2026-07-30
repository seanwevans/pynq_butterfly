# Script ownership and support policy

The repository root contains project metadata and only the compatibility entry
points documented in the top-level [README](../README.md). Automation belongs in
this hierarchy so that a command's path identifies its owner and execution
environment.

## Directory ownership

| Directory | Owner and purpose |
| --- | --- |
| `vivado/` | End-to-end Vivado orchestration and overlay build launchers. |
| `synth/` | RTL compilation, synthesis, and implementation commands. |
| `package/` | Vivado Tcl for staging and packaging reusable IP. |
| `integrate/` | Block-design integration, implementation, and timing-recovery Tcl. |
| `sim/` | Simulation launchers, regression compositions, and result checkers. |
| `board/install/` | Host-side preparation and installation onto a board. |
| `board/run/` | Commands and Python programs intended to execute on a board. |
| `vectors/` | Test-vector generation and banking verification. |
| `archive/` | Historical branch, commit, patch, repair, finalization, and narrowly scoped recovery procedures. |

## Naming

Use an action-oriented `snake_case` name. Shell launchers end in `.sh`, Vivado
programs in `.tcl`, and Python utilities in `.py`. Prefer the established verbs:
`build_` for orchestration, `compile_`/`implement_`/`synthesize_` for synthesis,
`package_` and `integrate_` for those phases, `run_`/`check_` for simulation,
and `install_` or `run_` below `board/`. Do not encode a one-off incident or Git
operation as a maintained command; place historical material in `archive/` or
document the relevant commit instead.

## Prerequisites and invocation

Run host commands from any working directory; maintained launchers derive the
repository root from their own location. Depending on the command, prerequisites
include Bash, Python 3, Icarus Verilog, OpenFHE, Vivado 2024.1, and the PYNQ/XRT
board environment. Individual commands validate the tools and artifacts they
need. Board installation additionally requires SSH/SCP access to the configured
PYNQ-Z2 host.

Invoke commands from the repository root with their full path, for example:

```bash
scripts/run_sim_regression.sh
scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.sh
scripts/board/install/install_bv_keyreuse_multi_pair_session_board.sh VECTOR_DIRECTORY
```

## Generated RTL fixtures

`generate_fixtures.py` is the single entry point for the reproducible fixtures
under `rtl/generated_*`. It derives them from the committed two-tower OpenFHE
vectors and requires Python 3 with NumPy installed. Regenerate them with:

```bash
scripts/generate_fixtures.py
```

CI and local validation can verify that the committed files are current without
rewriting the working tree:

```bash
scripts/generate_fixtures.py --check
```

The exact evaluation-domain fixtures under `tests/generated/` originate in an
external OpenFHE probe run and remain managed by the preparation programs in
`openfhe_eval_domain_bridge/`; they are not reproducible from committed inputs.

## Supported versus archival

Commands outside `archive/` are organized automation and may be used directly,
but the stable, supported entry-point set is the small list in the top-level
README. Internal commands can change as workflows evolve. Nothing in `archive/`
is a supported entry point: those files are retained only for provenance and may
depend on an old tree state, branch, checkpoint, or generated artifact.
