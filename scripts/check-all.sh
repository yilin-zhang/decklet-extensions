#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "[1/5] Check indentation"
./scripts/check-indent.sh

echo "[2/5] Byte compile"
./scripts/check-byte-compile.sh

echo "[3/5] Checkdoc"
./scripts/check-checkdoc.sh

echo "[4/5] Package lint"
./scripts/check-package-lint.sh

echo "[5/5] Tests"
./scripts/check-tests.sh

echo "All checks passed."
