#!/usr/bin/env bash
set -euo pipefail

# Idempotently commit the exact no-copy B64 BV-relinearization benchmark.
#
# Usage:
#   ./scripts/archive/commit_bv_relinearization_245pps.sh
#
# Optional environment variables:
#   BRANCH=evalmul-relinearization
#   PUSH=1
#   REMOTE=origin
#
# By default this stages only README.md. Add more paths on the command line:
#
#   ./scripts/archive/commit_bv_relinearization_245pps.sh \
#     README.md \
#     openfhe_eval_domain_bridge/run_fpga_bv_keyreuse_multi_pair_session.py

BRANCH="${BRANCH:-evalmul-relinearization}"
REMOTE="${REMOTE:-origin}"
PUSH="${PUSH:-0}"

COMMIT_MESSAGE="docs: document exact no-copy BV relinearization win"
BENCHMARK_MARKER="session_wall_relinearized_EvalMult_per_second=245.61"
EXACTNESS_MARKER="verified_residue_words=6291456"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "git is not installed"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "run this inside the pynq_butterfly repository"

cd "$REPO_ROOT"

CURRENT_BRANCH="$(git branch --show-current)"

[[ -n "$CURRENT_BRANCH" ]] \
  || die "detached HEAD; check out $BRANCH first"

[[ "$CURRENT_BRANCH" == "$BRANCH" ]] \
  || die "current branch is $CURRENT_BRANCH; expected $BRANCH"

# Refresh the remote branch when available. A fetch failure is not fatal for
# an entirely local workflow.
if git remote get-url "$REMOTE" >/dev/null 2>&1; then
  git fetch "$REMOTE" "$BRANCH" --tags
fi

contains_benchmark() {
  local ref="$1"

  git rev-parse --verify --quiet "$ref" >/dev/null \
    || return 1

  git show "$ref:README.md" 2>/dev/null \
    | grep -Fq "$BENCHMARK_MARKER" \
    || return 1

  git show "$ref:README.md" 2>/dev/null \
    | grep -Fq "$EXACTNESS_MARKER"
}

find_benchmark_commit() {
  local ref="$1"

  git log "$ref" \
    --fixed-strings \
    --grep="^${COMMIT_MESSAGE}$" \
    --format='%H' \
    -n 1 2>/dev/null \
    || true
}

# The benchmark may already exist locally.
if contains_benchmark "$BRANCH"; then
  SHA="$(find_benchmark_commit "$BRANCH")"

  if [[ -z "$SHA" ]]; then
    SHA="$(git rev-parse "$BRANCH")"
  fi

  printf 'already committed locally\n'
  printf 'branch: %s\n' "$BRANCH"
  printf 'commit: %s\n' "$SHA"
  exit 0
fi

# It may already exist on GitHub even when the local branch has not fetched or
# fast-forwarded to it.
REMOTE_REF="$REMOTE/$BRANCH"

if contains_benchmark "$REMOTE_REF"; then
  SHA="$(find_benchmark_commit "$REMOTE_REF")"

  if [[ -z "$SHA" ]]; then
    SHA="$(git rev-parse "$REMOTE_REF")"
  fi

  printf 'already committed on %s\n' "$REMOTE_REF"
  printf 'commit: %s\n' "$SHA"
  printf '\n'
  printf 'To update the local branch without creating another commit:\n'
  printf '  git merge --ff-only %q\n' "$REMOTE_REF"
  exit 0
fi

[[ -f README.md ]] \
  || die "README.md is missing"

grep -Fq "$BENCHMARK_MARKER" README.md \
  || die "README.md does not contain the 245.61/s benchmark marker"

grep -Fq "$EXACTNESS_MARKER" README.md \
  || die "README.md does not contain the 6,291,456-residue exactness marker"

if (( $# > 0 )); then
  PATHS=("$@")
else
  PATHS=(README.md)
fi

for path in "${PATHS[@]}"; do
  [[ -e "$path" ]] \
    || die "requested commit path does not exist: $path"
done

git add -- "${PATHS[@]}"

if git diff --cached --quiet; then
  die "nothing staged; the benchmark is not present in branch history"
fi

git commit -m "$COMMIT_MESSAGE"

SHA="$(git rev-parse HEAD)"

printf '\ncommitted benchmark\n'
printf 'branch: %s\n' "$BRANCH"
printf 'commit: %s\n' "$SHA"
printf 'message: %s\n' "$COMMIT_MESSAGE"

if [[ "$PUSH" == "1" ]]; then
  git push "$REMOTE" "$BRANCH"
  printf 'pushed: %s/%s\n' "$REMOTE" "$BRANCH"
else
  printf '\nNot pushed. Push with:\n'
  printf '  git push %q %q\n' "$REMOTE" "$BRANCH"
fi
