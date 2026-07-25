# Tar-stream vector installation fix

The previous installer used:

```bash
scp -r "$VECTOR_DIR/." "$BOARD_HOST:$REMOTE_VECTOR_STAGE/"
```

The installed OpenSSH `scp` rejects that source spelling:

```text
scp: error: unexpected filename: .
```

The fixed installer streams the directory contents with `tar` over SSH and
verifies `metadata.json` before replacing the live vector tree.

Because the bitstream, HWH, runner, and board shell script were already copied
successfully, the smaller repair script can upload only the missing vectors:

```bash
./repair_bv_keyreuse_multi_pair_session_vectors.sh
```

Or rerun the complete corrected installer:

```bash
./install_bv_keyreuse_multi_pair_session_board.sh
```

Existing board benchmark results are preserved.
