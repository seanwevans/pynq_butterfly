# Timing architecture

Supported overlays use a 100 MHz arithmetic clock and a 150 MHz DMA/PS HP-port
clock. Builds target the PYNQ-Z2 (`XC7Z020`) with Vivado 2024.1 and the
`Performance_ExplorePostRoutePhysOpt` strategy.

Timing closure depends on the registered BV accumulator boundary and explicit
clock-domain separation, not on adding arithmetic resources. Reproducible
current figures are summarized in [`../results/benchmark-summary.md`](../results/benchmark-summary.md).
The timing sweeps and recovery notes that led here are retained in
[`../history/`](../history/).
