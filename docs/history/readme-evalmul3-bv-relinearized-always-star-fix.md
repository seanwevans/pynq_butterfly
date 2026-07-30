# Icarus `always_comb` event-loop workaround

The latest trace proves that vector loading and simulation time zero both
complete. `vvp` reaches the first positive clock edge and then spends the rest
of the timeout processing events at that same simulation time.

That localizes the problem to combinational settling after the synchronous
reset assignments. Seven `always_comb` processes remain across the connected
EvalMul3, BV-MAC, and fused wrapper modules. Icarus implements extra
`always_comb` semantics and emits warnings that it broadens constant-select
sensitivity. With nested packed arrays and several mutually connected AXI
signals, that can create a pathological delta-cycle event storm.

This patch changes all seven blocks from:

```systemverilog
always_comb
```

to the synthesis-equivalent and more conservative:

```systemverilog
always @*
```

No equations, assignments, state transitions, FIFOs, protocols, or valid-cycle
behavior change.

The startup trace now uses `$strobe`, which runs after nonblocking assignments
settle and prints the wrapper and both inner states.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_relinearized_iverilog_always_star_fix.zip

./scripts/sim/run_evalmul3_bv_relinearized_checkpoint.sh
```

The expected startup is:

```text
TRACE: settled clock edge time=5000 reset_n=0 state=0 eval_state=0 bv_state=0
TRACE: settled clock edge time=15000 ...
```

Reaching the second edge confirms that the reset-edge delta storm is gone.
