#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

  printf 'Checkdoc %s\n' "${main_file#./}"
  emacs --batch --eval "(progn
    (require 'checkdoc)
    (unless (checkdoc-file \"$main_file\")
      (princ \"checkdoc failed\\n\")
      (kill-emacs 1)))"
done
