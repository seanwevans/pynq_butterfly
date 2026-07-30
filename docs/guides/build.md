# Build guide

Build the supported dual-clock overlay with:

```bash
scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.sh
```

Vivado 2024.1 and the PYNQ-Z2 board files are required. Build artifacts and the
machine-readable summary are written below `deploy/`. Older build recipes in
[`../history/`](../history/) reproduce checkpoints but are not supported entry points.
