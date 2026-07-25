# Icarus packed-lane elaboration fix

The vector conversion passed. The RTL failure is an Icarus elaboration
limitation, not an arithmetic error.

The core declared nested packed arrays such as:

```systemverilog
logic [1:0][1:0][31:0] multiplier_a;
```

Vivado accepts a procedural loop variable as the first packed-array selector,
but Icarus requires that selector to be constant during elaboration. The
reported failures at lines 272–290 and 409–441 are exactly those two loops.

This patch expands both two-lane loops into explicit constant lane 0 and lane 1
assignments. It does not change the protocol, arithmetic, latency, or expected
resource count.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  bv_keyswitch_mac_iverilog_lane_fix.zip

./run_bv_keyswitch_mac_checkpoint.sh
```
