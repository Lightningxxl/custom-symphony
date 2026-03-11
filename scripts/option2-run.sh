#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ELIXIR_DIR="$ROOT_DIR/elixir"
WORKFLOW_PATH="${1:-$ELIXIR_DIR/WORKFLOW.md}"

if ! command -v mise >/dev/null 2>&1; then
  echo "error: mise is not installed. Install from https://mise.jdx.dev/"
  exit 1
fi

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "warning: LINEAR_API_KEY is not set. Symphony can start but cannot read Linear issues."
fi

cd "$ELIXIR_DIR"
mise trust
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  "$WORKFLOW_PATH"
