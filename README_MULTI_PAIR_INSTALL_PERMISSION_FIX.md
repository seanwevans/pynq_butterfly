# Multi-pair installer permission fix

The failed install was caused by this old cleanup:

```bash
rm -rf "$REMOTE_DIR/vectors" "$REMOTE_DIR/results"
```

Board benchmarks run under `sudo -i`, so files under `results/` were owned by
root. The unprivileged `xilinx` SSH installer could delete `vectors/`, then
failed on `results/`. Because the installer uses `set -e`, it stopped before
uploading replacement vectors. That explains the subsequent missing
`vectors/metadata.json`.

The fixed installer:

- never removes benchmark results;
- uploads vectors into `.vectors.installing`;
- replaces the live vector tree only after the upload succeeds.

## One-time repair

On the board:

```bash
ssh xilinx@pynq
sudo -i

REMOTE=/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session

rm -rf \
  "$REMOTE/vectors" \
  "$REMOTE/.vectors.installing"

chown -R xilinx:xilinx "$REMOTE"

exit
exit
```

## Apply the installer fix and reinstall

From WSL:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_multi_pair_session_install_permission_fix.zip

./install_bv_keyreuse_multi_pair_session_board.sh
```

Then rerun B8 normally.
