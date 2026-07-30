# Timing-constraint correction

The original memory checkpoint synthesized the functional top directly.
Its schedule inputs were top-level ports, so Vivado selected an
unconstrained path from `stage` into a BRAM address pin. That produced a
blank `wns_ns` despite a 7.455 ns datapath.

This correction adds a synthesis-only registered shell around the
already-passing functional checkpoint and applies explicit zero-cycle
input/output delays relative to the 100 MHz clock.

The functional RTL and testbench behavior are unchanged.
