# Vivado module-reference wrapper fix

Vivado reached the block design and rejected the accelerator module reference:

```text
Reference 'evalmul3_two_tower_axis_dma_wrapper' contains top file
...evalmul3_two_tower_axis_dma_wrapper.sv of type SystemVerilog.
This type is not allowed as the top file in the reference.
```

The arithmetic core may remain SystemVerilog, but Vivado requires a block-design
module-reference top to be Verilog or VHDL.

This patch adds an equivalent Verilog-2001 shell:

```text
rtl/evalmul3_two_tower_axis_dma_wrapper.v
```

and updates the Tcl build to use it. The obsolete `.sv` wrapper may remain in
the working tree because it is no longer added to the Vivado project.

The build script is also hardened:

- it deletes the failed build directory before rebuilding;
- it removes stale deploy artifacts;
- it requires the exact Vivado PASS marker before copying reports;
- it no longer treats Vivado's occasional zero exit status after a Tcl error as
  success.

Apply and rebuild:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_dma_verilog_wrapper_fix.zip

./scripts/vivado/build_evalmul3_dma_overlay.sh
```
