# CRLF PASS-marker and no-rebuild finalization fix

Vivado completed successfully and wrote:

```text
PASS: fused evaluation-domain DMA overlay routed at 100 MHz
```

The shell script nevertheless rejected the marker because Windows Vivado wrote
`build_summary.txt` with CRLF line endings. `grep -Fxq` compared the line
including the hidden carriage return.

This patch makes the build script CRLF-tolerant:

```bash
tr -d '\r' <"$summary" | grep -Fxq "$pass_marker"
```

Because the bitstream and HWH already exist, do **not** rerun Vivado. Finalize
the successful existing build:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_dma_crlf_finalize_fix.zip

./finalize_evalmul3_dma_overlay.sh
```

That verifies the normalized PASS marker and copies the runner and routed
reports into the deploy directory without deleting or rebuilding anything.
