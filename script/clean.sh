#!/usr/bin/env bash
# Remove build artifacts and downloaded dependencies to reclaim disk space.
# Keeps source files intact.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

remove_if_exists() {
  local path="$1"
  if [ -e "$path" ]; then
    echo "▶ removing $path"
    rm -rf "$path"
  else
    echo "  $path (skipped, not present)"
  fi
}

remove_if_exists .build
remove_if_exists dist
remove_if_exists .swiftpm

echo "✓ clean complete"
echo "  next: swift build && swift test"
