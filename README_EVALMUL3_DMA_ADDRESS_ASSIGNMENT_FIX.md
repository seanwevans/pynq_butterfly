# DMA address-assignment fix

Vivado successfully auto-assigned the expected DMA control mapping:

```text
/dma/S_AXI_LITE/Reg -> /ps7/Data
0x4040_0000 [64K]
```

The build then attempted to rewrite `offset` and `range` on the already
assigned slave segment:

```text
ERROR: Cannot change read-only property 'offset'
```

That rewrite is unnecessary. The patch removes it and keeps:

```tcl
assign_bd_address
validate_bd_design
```

Apply and rebuild:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_dma_address_assignment_fix.zip

./scripts/vivado/build_evalmul3_dma_overlay.sh
```

The build script already deletes the failed project before rebuilding.
