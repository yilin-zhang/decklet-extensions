#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_LINT_GIT_URL="https://github.com/purcell/package-lint.git"
PACKAGE_LINT_COMMIT="1c37329703a507fa357302cf6fc29d4f2fe631a8"
CACHE_DIR="$REPO_ROOT/scripts/.cache"
PACKAGE_LINT_DIR="$CACHE_DIR/package-lint/$PACKAGE_LINT_COMMIT"
PACKAGE_USER_DIR="$CACHE_DIR/package-lint-elpa"

if [[ ! -f "$PACKAGE_LINT_DIR/package-lint.el" ]] && \
   command -v git >/dev/null 2>&1; then
  mkdir -p "$PACKAGE_LINT_DIR"
  git init "$PACKAGE_LINT_DIR" >/dev/null 2>&1 || true
  git -C "$PACKAGE_LINT_DIR" remote add origin "$PACKAGE_LINT_GIT_URL" >/dev/null 2>&1 || true
  git -C "$PACKAGE_LINT_DIR" fetch --depth 1 origin "$PACKAGE_LINT_COMMIT" >/dev/null 2>&1 || true
  git -C "$PACKAGE_LINT_DIR" checkout --detach FETCH_HEAD >/dev/null 2>&1 || true
fi

if [[ ! -f "$PACKAGE_LINT_DIR/package-lint.el" ]]; then
  echo "Error: failed to fetch package-lint source" >&2
  exit 1
fi

cd "$REPO_ROOT"

pkg_dirs="$(find . -maxdepth 2 -name 'decklet-*.el' -not -path '*/tests/*' -not -path '*/.venv/*' -type f \
            | xargs -n1 dirname | sort -u)"

# package-lint initializes package.el internally.  Keep that initialization
# in a persistent, isolated cache so later checks can also run offline.
mkdir -p "$PACKAGE_USER_DIR"

printf '%s\n' "$pkg_dirs" | while IFS= read -r pkg_dir; do
  pkg_name="$(basename "$pkg_dir")"
  main_file="$pkg_name.el"
  [ -f "$pkg_dir/$main_file" ] || continue

  printf 'Package lint %s\n' "${pkg_dir#./}"
  (cd "$pkg_dir" && \
    DECKLET_PACKAGE_USER_DIR="$PACKAGE_USER_DIR" \
    DECKLET_EXT_MAIN_FILE="$main_file" \
    emacs --batch -Q \
      --eval '(setq package-user-dir (getenv "DECKLET_PACKAGE_USER_DIR"))' \
      -L . \
      -L "$PACKAGE_LINT_DIR" \
      -l "$PACKAGE_LINT_DIR/package-lint.el" \
      -l "$REPO_ROOT/scripts/check-package-lint.el" \
      -f decklet-ext-check-configure-package-lint \
      -f package-lint-batch-and-exit \
      ./*.el)
done
