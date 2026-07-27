# Vivado report whitespace normalization fix

The CRLF-only fix removed carriage returns, but Vivado's fixed-width tables
still contain spaces at the ends of lines, and the reports end with extra blank
lines. `git diff --cached --check` correctly continued to reject them.

This patch normalizes generated `.rpt` and `.txt` files by:

```text
removing CRLF carriage returns
removing trailing spaces and tabs from every line
removing blank lines at EOF
writing exactly one final newline
```

No HDL, scripts, bitstreams, or HWH files are modified.

Apply and rerun the release helper:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_release_report_whitespace_fix.zip

./scripts/archive/commit_evalmul3_833pps.sh --push
```

The earlier attempts stopped before `git commit`, so rerunning is safe.
