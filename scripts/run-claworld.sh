#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/Projects}"
CLAWORLD_ROOT="${CLAWORLD_ROOT:-$PROJECTS_ROOT/claworld}"
WORKFLOW_PATH="${WORKFLOW_PATH:-$CLAWORLD_ROOT/WORKFLOW.md}"

if [[ ! -f "$WORKFLOW_PATH" ]]; then
  echo "error: missing Claworld workflow at $WORKFLOW_PATH"
  echo "set CLAWORLD_ROOT or WORKFLOW_PATH to your local Claworld checkout."
  exit 1
fi

if [[ -z "${SYMPHONY_WORKSPACE_ROOT:-}" ]]; then
  export SYMPHONY_WORKSPACE_ROOT="$PROJECTS_ROOT/claworld-workspaces"
fi

if [[ -z "${OPENCLAW_REF_ROOT:-}" ]]; then
  export OPENCLAW_REF_ROOT="$PROJECTS_ROOT/openclaw"
fi

if [[ -z "${CLAWDBOT_FEISHU_REF_ROOT:-}" ]]; then
  if [[ -d "$PROJECTS_ROOT/clawdbot-feishu" ]]; then
    export CLAWDBOT_FEISHU_REF_ROOT="$PROJECTS_ROOT/clawdbot-feishu"
  else
    export CLAWDBOT_FEISHU_REF_ROOT="$PROJECTS_ROOT/clawbot-feishu"
  fi
fi

mkdir -p "$SYMPHONY_WORKSPACE_ROOT"

echo "Starting Symphony for Claworld:"
echo "  workflow: $WORKFLOW_PATH"
echo "  workspaces: $SYMPHONY_WORKSPACE_ROOT"
echo "  openclaw ref: $OPENCLAW_REF_ROOT"
echo "  clawdbot-feishu ref: $CLAWDBOT_FEISHU_REF_ROOT"

exec "$ROOT_DIR/scripts/option2-run.sh" "$WORKFLOW_PATH"
