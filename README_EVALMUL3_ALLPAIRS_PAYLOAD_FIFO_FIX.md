# Registered EV12 payload FIFO fix

The latest trace advanced through all internally injected header states and
stopped as the sequencer attempted to enter payload forwarding:

```text
outer_state=9
core_state=3
```

These are `STATE_INJECT_BATCH_COUNT` and the child core's
`INPUT_BATCH_COUNT`. The next transition enabled the original direct payload
path:

```text
external TVALID/TDATA
        |
outer combinational mux
        |
child core
        |
child TREADY
        |
outer external TREADY
```

Icarus again stopped advancing simulation time at that boundary.

This patch inserts a registered two-word FIFO between the external EV12 stream
and the legacy two-tower core. External readiness now depends only on the FIFO
occupancy, never directly on the child core's combinational readiness.

The FIFO does not reduce steady-state bandwidth:

```text
cycle 0: enqueue
cycle 1+: simultaneous enqueue and dequeue every cycle
```

The final word of each pair is buffered with an internally generated per-pair
TLAST. The sequencer enters `STATE_WAIT_PAIR_OUTPUT` only after the child core
has consumed that final buffered word.

Apply over the existing checkpoint and diagnostic patches:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_allpairs_payload_fifo_fix.zip

./scripts/sim/run_evalmul3_allpairs_checkpoint.sh
```

Expected trace progression:

```text
outer_state=9
outer_state=10
accepted_ev12_words=...
pair 0 complete
...
PASS: all-pair EVPT/EV12 exact
```
