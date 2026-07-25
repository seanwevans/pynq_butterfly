# Single-CMA-arena B64 allocation fix

The B64 persistent-output run was exact, but `all-cma` fell back:

```text
all_cma_fallback_reason=RuntimeError: BO allocation failed: std::bad_alloc
send_buffer_mode=reuse-copy
median_dma_call_us=261731.38
median_session_wall_us=794850.65
median_copy_flush_us=532602.66
```

The DMA-call interval reached:

```text
4089.55 us per ciphertext
244.53/s
```

That is only about 0.14% below the measured OpenFHE CPU result, but the
`reuse-copy` wall time is not competitive.

## Fix

The new preferred mode allocates one contiguous MM2S CMA arena:

```text
6 pair frames: 196.50 MiB
S2MM output:    24.00 MiB
total:         220.50 MiB
```

Each pair is sent from the arena with the DMA driver's `start` and `nbytes`
arguments. This reduces the MM2S allocation from six BOs to one BO while
keeping each actual DMA transfer below the 26-bit length limit.

Allocation order is also changed:

```text
1. allocate and prefill MM2S arena;
2. allocate S2MM output;
3. fall back to six separate MM2S BOs;
4. fall back to reuse-copy only if both no-copy layouts fail.
```

## Apply and reinstall

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_multi_pair_session_cma_arena_board_fix.zip

./install_bv_keyreuse_multi_pair_session_board.sh
```

After a fresh board reboot, run B64:

```bash
REMOTE=/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session

"$REMOTE/run_bv_keyreuse_multi_pair_session_board.sh" \
  "$REMOTE" \
  64 \
  5 | tee "$REMOTE/results/batch_64_arena.log"
```

The decisive field is:

```text
send_buffer_mode=arena-cma
median_copy_flush_us=0.00
```

The runner still validates all 6,291,456 returned residue words exactly.
