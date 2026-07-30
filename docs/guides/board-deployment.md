# Board deployment guide

Install an already-built overlay and an OpenFHE vector directory with:

```bash
scripts/board/install/install_bv_keyreuse_multi_pair_session_board.sh VECTOR_DIRECTORY
```

The installer places the bitstream, hardware handoff, runner, and vectors on the
PYNQ-Z2. Use the scripts under `scripts/board/` for maintained board operations;
root wrappers exist only for compatibility.
