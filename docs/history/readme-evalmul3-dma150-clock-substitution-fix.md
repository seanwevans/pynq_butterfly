# Tcl variable-substitution fix

Vivado rejected the PS clock parameters because the Tcl values were written as:

```tcl
CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {$core_clock_mhz}
CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {$memory_clock_mhz}
```

Inside a Tcl list, braces suppress variable substitution, so Vivado received
the literal strings `$core_clock_mhz` and `$memory_clock_mhz`.

The corrected form is:

```tcl
CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $core_clock_mhz
CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ $memory_clock_mhz
```

Apply and rebuild:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_dma150_clock_substitution_fix.zip

./scripts/vivado/build_evalmul3_dma150_overlay.sh
```

The build helper already deletes the failed working directory before invoking
Vivado, so no manual cleanup is required.
