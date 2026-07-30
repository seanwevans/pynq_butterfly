# Timing fix v2

Vivado 2024.1 rejected `remove_from_collection` in the prior Tcl script.

This version obtains the timing-constrained ports directly with Vivado
object filters:

    get_ports -filter {DIRECTION == IN && NAME != clk}
    get_ports -filter {DIRECTION == OUT}

The registered synthesis shell and functional RTL are unchanged.
