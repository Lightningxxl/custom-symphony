#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ELIXIR_DIR="$ROOT_DIR/elixir"

if ! command -v mise >/dev/null 2>&1; then
  echo "error: mise is not installed. Install from https://mise.jdx.dev/"
  exit 1
fi

cd "$ELIXIR_DIR"
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build

echo "Option 2 setup completed."

