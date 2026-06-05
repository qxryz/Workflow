#!/usr/bin/env bash
# Run repository linters. Fails fast on any violation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint not installed. Install with: brew install swiftlint" >&2
  exit 1
fi

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "swiftformat not installed. Install with: brew install swiftformat" >&2
  exit 1
fi

echo "▶ swiftlint (lint only)"
swiftlint lint --quiet

echo "▶ swiftformat (lint only)"
swiftformat --lint .

if [ -d website ]; then
  if [ -f website/package.json ]; then
    if grep -q '"lint"' website/package.json; then
      echo "▶ npm run lint (website)"
      (cd website && npm run lint --silent)
    fi
  fi
fi

echo "✓ lint clean"
