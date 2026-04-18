#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "[1/4] Check indentation"
./scripts/check-indent.sh

echo "[2/4] Byte compile"
./scripts/check-byte-compile.sh

echo "[3/4] Checkdoc"
./scripts/check-checkdoc.sh

echo "[4/4] Tests"
./scripts/check-tests.sh

echo "All checks passed."
