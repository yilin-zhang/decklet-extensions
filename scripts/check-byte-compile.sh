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

pkg_dirs="$(find . -maxdepth 2 -name 'decklet-*.el' -not -path '*/tests/*' -not -path '*/.venv/*' -type f \
            | xargs -n1 dirname | sort -u)"

if [ -z "$pkg_dirs" ]; then
  printf 'No extension package source files found.\n'
  exit 0
fi

printf '%s\n' "$pkg_dirs" | while IFS= read -r pkg_dir; do
  pkg_name="$(basename "$pkg_dir")"
  main_file="$pkg_dir/$pkg_name.el"
  [ -f "$main_file" ] || continue

  printf 'Byte-compiling %s\n' "${pkg_dir#./}"
  (cd "$pkg_dir" && \
    emacs --batch \
      -L . \
      -L "$FSRS_DIR" \
      -L "$CORE_DIR" \
      -f batch-byte-compile "$pkg_name.el")
  rm -f "$pkg_dir"/*.elc
done
