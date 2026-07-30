# Build guide

Build the supported dual-clock overlay with:

```bash
scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.sh
```

Vivado 2024.1 and the PYNQ-Z2 board files are required. Stable board and payload
metadata is kept in `deploy/<overlay>/manifest.json`. The build stages its files
outside the source tree and packages a complete payload in
`artifacts/deploy/<overlay>/`. During packaging, checksums, sizes, the timestamp,
and `package_summary.txt` are generated in that ignored output directory; builds
therefore do not rewrite checked-in inventory or summary data. Set
`PYNQ_ARTIFACT_ROOT` to choose another package root. Older build recipes in
[`../history/`](../history/) reproduce checkpoints but are not supported entry points.
