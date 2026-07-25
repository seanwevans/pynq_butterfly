# Vivado 2024.1 OOC physical-flow fix

The design itself routed successfully:

```text
WNS=+0.147 ns
TNS=0
WHS=+0.025 ns
THS=0
```

The build stopped afterward because Vivado 2024.1 does not support:

```tcl
phys_opt_design -post_route
```

Post-route mode is inferred automatically because the design is already
routed. The correct command is:

```tcl
phys_opt_design -directive AggressiveExplore
```

This patch also resolves the OOC clock-model warning by assigning the clock
port the same FCLK0 buffer location used by the complete PYNQ-Z2 overlay:

```tcl
set_property HD.CLK_SRC BUFGCTRL_X0Y17 [get_ports clk]
```

That makes the rerun's slack more representative than the initial ideal-clock
result.

## Apply and rerun

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  bv_keyswitch_mac_ooc_vivado_2024_1_fix.zip

./build_bv_keyswitch_mac_ooc.sh
```

The build directory is recreated automatically.
