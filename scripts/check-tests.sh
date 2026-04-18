#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${DECKLET_CORE_DIR:-$REPO_ROOT/../decklet}"

if [ ! -d "$CORE_DIR" ]; then
  printf 'Decklet core repo not found at %s\n' "$CORE_DIR" >&2
  exit 1
fi

FSRS_DIR="$CORE_DIR"
if [ -x "$CORE_DIR/scripts/check-deps.sh" ]; then
  FSRS_DIR="$($CORE_DIR/scripts/check-deps.sh)"
fi

cd "$REPO_ROOT"

test_files="$(find . -path './*/tests/*-test.el' -type f | sort)"

if [ -z "$test_files" ]; then
  printf 'No extension test files found.\n'
  exit 0
fi

printf '%s\n' "$test_files" | while IFS= read -r test_file; do
  pkg_dir="$(dirname "$(dirname "$test_file")")"
  test_dir="$(dirname "$test_file")"
  test_name="${test_file#./}"

  printf 'Running %s\n' "$test_name"
  emacs --batch \
    -L "$FSRS_DIR" \
    -L "$CORE_DIR" \
    -L "$pkg_dir" \
    -L "$test_dir" \
    -l "$test_file" \
    -f ert-run-tests-batch-and-exit
done
