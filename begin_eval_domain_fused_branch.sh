#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-eval-domain-ciphertext-fused}"

current="$(
  git branch --show-current
)"

if [[ "$current" == "$BRANCH" ]]; then
  echo "Already on $BRANCH"
  exit 0
fi

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch "$BRANCH"
else
  git switch -c "$BRANCH"
fi
