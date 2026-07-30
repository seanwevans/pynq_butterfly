# Vivado timing-path property fix

The implementation reached the reporting stage. The failure is only this
unsupported property query:

```tcl
get_property PATH_GROUP $worst_path
```

In Vivado 2024.1, the returned `timing_path` object does not expose a
`PATH_GROUP` property. The design has only one timing clock (`core_clk`), so
the query is unnecessary.

This patch removes the invalid property lookup and records:

```text
BV_KEYSWITCH_MAC_OOC_CLOCK=core_clk
```

All WNS, failing-path, utilization, exact 64-DSP, and timing-closure checks
remain unchanged.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  bv_keyswitch_mac_ooc_timing_path_property_fix.zip

./scripts/vivado/build_bv_keyswitch_mac_ooc.sh
```
