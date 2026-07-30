# All-pair simulation progress/watchdog fix

The `N=8`, three-pair simulation should finish in seconds. A silent run lasting
longer than roughly 20 seconds is not expected.

This patch adds:

- visible compile and simulation stage markers;
- progress messages before and after EVPT and EV12 input;
- a message when each tower pair completes;
- a 10,000-cycle RTL watchdog that prints the outer sequencer state, inner
  two-tower state, FIFO occupancy, and output count;
- 60-second compile and 20-second real-time execution limits.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

# Stop the currently silent run first with Ctrl+C.

unzip -o \
  evalmul3_allpairs_progress_watchdog_fix.zip

./scripts/sim/run_evalmul3_allpairs_checkpoint.sh
```

The new output will identify whether the delay is in Icarus compilation or in
a specific protocol state.
