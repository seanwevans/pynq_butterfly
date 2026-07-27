# Timeout-status propagation fix

The previous watchdog wrapper used:

```bash
if ! timeout ...; then
    status=$?
fi
```

Inside that branch, `$?` is the status of the inverted `!` expression, so it
became `0` even when `timeout` killed `vvp` with status `124`. That produced the
contradictory output:

```text
error: vvp failed with status 0
PASS: all-pair RTL checkpoint complete
```

This patch captures the actual `timeout`/`vvp` status before testing it. A
timeout or simulator failure now propagates out of the checkpoint script.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_allpairs_timeout_status_fix.zip

./scripts/sim/run_evalmul3_allpairs_checkpoint.sh
```

The next run should either emit the RTL watchdog diagnostics or terminate with
the genuine process status, most likely `124` for the current silent hang.
