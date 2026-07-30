# Vivado report CRLF fix

The release script stopped at `git diff --cached --check` because Windows
Vivado wrote the routed reports with CRLF endings. Git displayed the carriage
return as trailing whitespace on every line.

Apply this patch and rerun the release helper:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_release_report_crlf_fix.zip

./scripts/archive/commit_evalmul3_833pps.sh --push
```

The patched helper normalizes only generated `.rpt` and `.txt` files under:

```text
deploy/evalmul3_two_tower_dma/
```

It then restages the explicit release allowlist and performs the same
whitespace check.

The earlier failed attempt created no commit or tag. Its staged files are safe;
rerunning `git add` refreshes them after normalization.
