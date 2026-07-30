# Documentation

Documents are organized by subject and support status. Current contracts live
in architecture and guides; measured evidence lives in results; superseded
checkpoints and investigations live in history.

## Start here

- [Quick start](guides/quick-start.md)
- [Stream protocol](architecture/protocol.md)
- [Current benchmark summary](results/benchmark-summary.md)

## Architecture

- [Protocol](architecture/protocol.md)
- [Arithmetic](architecture/arithmetic.md)
- [RTL](architecture/rtl.md)
- [Memory](architecture/memory.md)
- [Timing](architecture/timing.md)
- [Evaluation-key reuse](architecture/evaluation-key-reuse.md)
- [Relinearization boundary](architecture/relinearization-boundary.md)
- [Detailed session protocol](architecture/session-protocol.md)

## Workflows

- [Build](guides/build.md)
- [Board deployment](guides/board-deployment.md)
- [OpenFHE integration](guides/openfhe.md)

## Benchmark evidence

- [Benchmark summary](results/benchmark-summary.md)
- [`docs/results/`](results/) contains the individual simulation, implementation,
  board, and sweep records. Filenames identify the measured subsystem rather
  than the date it happened.

## Historical lineage

The [historical lineage index](history/readme.md) organizes superseded fixes,
investigations, recovery notes, release notes, and checkpoints. These records explain how the current
architecture was reached, but they are not supported procedures. Current pages
link into history when that lineage is useful; old notes are not duplicated into
the current contract.
