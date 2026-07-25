# Icarus delta-cycle performance fix

The simulation did not reach the first pair. That means this is not yet a
protocol deadlock: `vvp` was spending the entire 180 seconds before the first
dozen clock edges.

The compile warning identified the cause:

```text
constant selects in always_* processes are not currently supported
(all bits will be included)
```

The final modular-add `always_comb` block dynamically indexes four FIFO
memories and then selects 32-bit lanes. Icarus broadens that sensitivity set,
which can cause extreme delta-cycle churn.

This patch replaces only that `always_comb` block with continuous assignments:

```text
FIFO heads
    -> four 33-bit additions
    -> four conditional modular reductions
```

The arithmetic, latency, state machines, FIFOs, and protocol are unchanged.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_relinearized_iverilog_delta_fix.zip

./run_evalmul3_bv_relinearized_checkpoint.sh
```

The constant-select warnings at the former line 562 should disappear. The
simulation should then reach:

```text
PROGRESS: pair 0 loading fused profile
```

If it later stops after a pair begins, that will expose an actual handshake or
alignment issue rather than simulator event churn.
