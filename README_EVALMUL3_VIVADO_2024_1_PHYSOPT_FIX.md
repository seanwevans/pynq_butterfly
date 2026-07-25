# Vivado 2024.1 physical-optimization syntax fix

Routing completed successfully, then Vivado stopped at:

```text
ERROR: [Common 17-170] Unknown option '-post_route'
```

In Vivado 2024.1, `phys_opt_design` determines whether it is running
post-place or post-route from the current design state. It does not accept an
explicit post-route command-line switch.

The corrected sequence is:

```tcl
route_design -directive NoTimingRelaxation
write_checkpoint -force routed_before_physopt.dcp
phys_opt_design -directive Explore
write_checkpoint -force routed.dcp
```

The raw routed checkpoint is now written before physical optimization, so a
later failure cannot throw away a successful route.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_vivado_2024_1_physopt_fix.zip

./build_evalmul3_ooc.sh
```

The full build must rerun because the previous non-project Vivado process
exited before writing a routed checkpoint.
