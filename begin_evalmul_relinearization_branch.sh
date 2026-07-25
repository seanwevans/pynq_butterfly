#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-evalmul-relinearization}"

if [[ "$(git branch --show-current)" == "$BRANCH" ]]; then
  echo "Already on $BRANCH"
elif git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch "$BRANCH"
else
  git switch -c "$BRANCH"
fi
