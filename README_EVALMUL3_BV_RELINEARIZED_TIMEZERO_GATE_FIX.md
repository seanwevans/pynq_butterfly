# Fused simulation time-zero memory-read gate

The second timeout still occurred before the first profile transaction. The
remaining time-zero hazard is dynamic reads from uninitialized FIFO memories
in all three connected modules.

At simulation time zero, FIFO pointers and counts are `X` until the first reset
clock edge. Icarus can spend extreme time resolving dynamic memory reads such
as:

```systemverilog
fifo_c0[fifo_read_pointer]
```

even though AXI `TVALID` is low and `TDATA` is semantically irrelevant.

This patch gates every output-side dynamic FIFO read:

```systemverilog
!reset_n || fifo_count == 0 ? 64'd0 : fifo[pointer]
```

It changes only invalid-cycle `TDATA`. Valid transfers, arithmetic, latency,
and synthesis behavior are unchanged.

The testbench also prints markers after each `$readmemh`, after `#1`, and for
the first clock edges. Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_relinearized_timezero_gate_fix.zip

./run_evalmul3_bv_relinearized_checkpoint.sh
```

The new trace will distinguish file loading, zero-time settling, and clocked
execution if another simulator issue remains.
