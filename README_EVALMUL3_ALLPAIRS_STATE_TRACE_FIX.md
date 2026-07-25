# EvalMul3 all-pair state-trace patch

The corrected process status confirms a real simulation stall. The earlier
10,000-cycle watchdog was too long to beat Icarus's real-time timeout.

This patch:

- reduces the RTL watchdog to 512 cycles;
- traces every outer sequencer state transition;
- traces every inner two-tower input-state transition;
- reports every 16 accepted EV12 payload words;
- emits a heartbeat every 64 clocks;
- gives `vvp` 60 real seconds so the RTL watchdog can print the final state.

The normal N=8, three-pair test should complete in substantially fewer than
512 cycles.

Apply and run:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o   evalmul3_allpairs_state_trace_fix.zip

./run_evalmul3_allpairs_checkpoint.sh
```

The last `TRACE`, `HEARTBEAT`, and watchdog lines will identify the exact
deadlocked state.
