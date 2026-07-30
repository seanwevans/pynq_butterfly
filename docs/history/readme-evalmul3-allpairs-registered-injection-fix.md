# Registered internal-header injection fix

The trace reached:

```text
outer_state=4
```

which is `STATE_BATCH_HEADER`, then simulation time stopped immediately after
that header was accepted. The next state was
`STATE_INJECT_PROFILE_COMMAND`.

The original sequencer drove the child core's AXI `TVALID`, `TDATA`, and
`TLAST` combinationally from the outer state while also consuming the child
core's combinational `TREADY`. Icarus entered a delta-cycle oscillation as soon
as the first internally generated `EVPF` command became active, so neither the
clock nor the cycle watchdog could advance.

This patch replaces that path with a registered one-word injection source:

```text
accept EV12 header
    |
register EVPF command
    |
child handshake
    |
register q
    |
child handshake
    |
register mu + TLAST
    |
register EVB3 command
    |
register batch count
    |
forward payload
```

The arithmetic core and external EVPT/EV12 protocol are unchanged.

Apply over the existing checkpoint and trace patches:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_allpairs_registered_injection_fix.zip

./scripts/sim/run_evalmul3_allpairs_checkpoint.sh
```

Expected progress now continues through outer states 5, 6, 7, 8, 9, and 10
instead of stopping after state 4.
