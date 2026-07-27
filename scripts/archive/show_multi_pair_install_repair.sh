#!/usr/bin/env bash
set -euo pipefail

BOARD_HOST="${1:-xilinx@pynq}"
REMOTE_DIR="${2:-/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session}"

cat <<EOF
The previous installer stopped after deleting vectors because root-owned
benchmark results could not be removed by the xilinx account.

Run this once on the board:

  ssh $BOARD_HOST
  sudo -i
  REMOTE='$REMOTE_DIR'
  rm -rf "\$REMOTE/vectors" "\$REMOTE/.vectors.installing"
  chown -R xilinx:xilinx "\$REMOTE"
  exit
  exit

Then rerun:

  ./scripts/board/install/install_bv_keyreuse_multi_pair_session_board.sh
EOF
