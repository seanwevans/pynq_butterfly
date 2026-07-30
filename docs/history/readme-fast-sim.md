# Fast full-polynomial integration checkpoint

The previous command was allowed to run silently through the complete
iterative arithmetic network. That is not an acceptable regression for
Icarus.

This checkpoint adds:

- an exact behavioral `modmul_core` simulation model;
- the same start/busy/done handshake;
- full q0 and q1 OpenFHE output comparison;
- progress output during profile loading and product execution;
- a hard product watchdog with internal state and phase counters;
- removal of the repeated Icarus `always_comb` sensitivity warnings.

The fast model is integration-only. Synthesis must continue to use the
real `modmul_core.sv`.

Compile with `-DFAST_MODMUL` and include
`modmul_core_fast_sim.sv` instead of `modmul_core.sv`.
