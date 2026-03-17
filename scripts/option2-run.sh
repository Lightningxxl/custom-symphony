#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ELIXIR_DIR="$ROOT_DIR/elixir"
WORKFLOW_PATH="${1:-$ELIXIR_DIR/WORKFLOW.md}"

workflow_uses_linear_tracker() {
  grep -Eq '^[[:space:]]*kind:[[:space:]]*linear([[:space:]]|$)' "$WORKFLOW_PATH"
}

workflow_uses_env_var() {
  local env_var="$1"
  local pattern
  printf -v pattern '^[[:space:]]*[a-z_]+:[[:space:]]*"?\\$%s"?([[:space:]]|$)' "$env_var"
  grep -Eq "$pattern" "$WORKFLOW_PATH"
}

require_env_var() {
  local env_var="$1"

  if [[ -z "${!env_var:-}" ]]; then
    echo "error: $env_var is required by $WORKFLOW_PATH"
    echo "hint: export $env_var in the launching shell or run 'source ~/.zshrc' before starting Symphony."
    exit 1
  fi
}

if ! command -v mise >/dev/null 2>&1; then
  echo "error: mise is not installed. Install from https://mise.jdx.dev/"
  exit 1
fi

if workflow_uses_linear_tracker; then
  if workflow_uses_env_var "LINEAR_API_KEY"; then
    require_env_var "LINEAR_API_KEY"
  fi

  if workflow_uses_env_var "LINEAR_PROJECT_SLUG_ID"; then
    require_env_var "LINEAR_PROJECT_SLUG_ID"
  fi
fi

cd "$ELIXIR_DIR"
mise trust
mise exec -- mix build
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  "$WORKFLOW_PATH"
