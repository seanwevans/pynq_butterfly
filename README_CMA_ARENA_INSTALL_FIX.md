# CMA-arena installer correction

The CMA-arena ZIP accidentally carried an older installer that still ran:

```bash
rm -rf "$REMOTE_DIR/vectors" "$REMOTE_DIR/results"
```

Because board results are root-owned, the unprivileged SSH account deleted the
vectors, failed on the results, and stopped before uploading the new runner.
That produced the subsequent missing `vectors/metadata.json`.

This correction combines:

```text
CMA-arena board runner
results-preserving installer
tar-over-SSH vector transfer
staged metadata verification
```

## Fast repair

The bitstream and HWH are already present. From WSL:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_multi_pair_session_cma_arena_install_fix.zip

./repair_bv_keyreuse_multi_pair_session_cma_arena_install.sh
```

This uploads the CMA-arena runner and restores the vectors without touching
existing results.

## Full corrected install

```bash
./install_bv_keyreuse_multi_pair_session_board.sh
```

## B64 run

Reboot the board, then:

```bash
ssh xilinx@pynq
sudo -i

REMOTE=/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session

"$REMOTE/run_bv_keyreuse_multi_pair_session_board.sh" \
  "$REMOTE" \
  64 \
  5 | tee "$REMOTE/results/batch_64_arena.log"
```

The target fields are:

```text
send_buffer_mode=arena-cma
median_copy_flush_us=0.00
```
