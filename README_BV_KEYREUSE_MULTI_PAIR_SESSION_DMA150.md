# Persistent-output multi-pair DMA150 overlay

Standalone result: ExploreNetDelayHigh, WNS +0.351 ns, 0 failing paths, 7372 LUTs, 6550 registers, 160 DSP48E1, no BRAM, 770 SRLs.

The overlay retains the proven 100 MHz core / 150 MHz DMA topology, 64-bit AXI DMA, 26-bit length, burst 16, DRE disabled, and 1024-word asynchronous AXIS FIFOs.

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o evalmul3_bv_keyreuse_multi_pair_session_dma150_overlay_checkpoint.zip
./build_bv_keyreuse_multi_pair_session_dma150_overlay.sh
```

Expected PASS marker:

```text
PASS: persistent-output multi-pair session dual-clock DMA overlay routed
```
