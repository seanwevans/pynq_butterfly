# Parallel two-tower dual-butterfly AXI checkpoint

This checkpoint wraps two complete 631810-cycle runtime-profile
dual-butterfly cores behind one 64-bit AXI4-Stream interface.

## Stream layout

Each 64-bit stream word is:

- bits 31:0: OpenFHE tower q0
- bits 63:32: OpenFHE tower q1

Profile frame:

- 16384 x 64-bit words
- 131072 bytes

Product input frame:

- 8193 x 64-bit words
- 65544 bytes

Product output frame:

- 4096 x 64-bit words
- 32768 bytes

Both towers consume and produce words in lockstep. The regression uses
randomized input gaps and randomized output backpressure and runs two
products after one profile load.

For Icarus, compile with `-DFAST_MODMUL` and
`modmul_core_fast_sim.sv`. The exact behavioral multiplier preserves
the arithmetic and handshake while making the full AXI integration
regression practical.

Synthesis must use the real `modmul_core.sv`.


## Timing-isolation revision

The complete PYNQ-Z2 route exposed this critical path:

    coefficient_store_a BRAM output
        -> butterfly input subtraction/mux
        -> modmul_core x_reg

Post-route WNS was -0.906 ns at 100 MHz.

The butterfly now captures `a`, `b`, `omega`, and `q` first and launches
the iterative multiplier on the following clock. This inserts one
pipeline boundary between the coefficient BRAM and multiplier.

Cost:

    12288 forward pairs + 12288 inverse pairs = 24576 clocks

New hardware target:

    607234 + 24576 = 631810 clocks
    6318.10 us at 100 MHz
