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

WORKFLOW_DIR="$(cd "$(dirname "$WORKFLOW_PATH")" && pwd)"

if REPO_ROOT="$(git -C "$WORKFLOW_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  REPO_ROOT="$CLAWORLD_ROOT"
fi

resolve_source_ref() {
  local ref
  local branch

  if ref="$(git -C "$REPO_ROOT" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "${ref#refs/remotes/}"
    return 0
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet refs/remotes/origin/main; then
    printf 'origin/main\n'
    return 0
  fi

  branch="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
  if [[ -n "$branch" ]]; then
    printf '%s\n' "$branch"
    return 0
  fi

  printf 'HEAD\n'
}

resolve_env_or_legacy() {
  local primary="$1"
  local legacy="$2"
  local fallback="${3:-}"

  if [[ -n "${!primary:-}" ]]; then
    printf '%s\n' "${!primary}"
    return 0
  fi

  if [[ -n "${!legacy:-}" ]]; then
    printf '%s\n' "${!legacy}"
    return 0
  fi

  printf '%s\n' "$fallback"
}

normalize_github_push_url() {
  local url="$1"
  local path

  case "$url" in
    https://github.com/*)
      path="${url#https://github.com/}"
      ;;
    ssh://git@github.com/*)
      path="${url#ssh://git@github.com/}"
      ;;
    git@github.com:*)
      path="${url#git@github.com:}"
      ;;
    *)
      printf '%s\n' "$url"
      return 0
      ;;
  esac

  path="${path%.git}"
  printf 'git@github.com:%s.git\n' "$path"
}

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

export CLAWORLD_CANONICAL_SOURCE_REPO="$(
  resolve_env_or_legacy "CLAWORLD_CANONICAL_SOURCE_REPO" "CLAWORLD_SOURCE_REPO_URL" "$REPO_ROOT"
)"
export CLAWORLD_SOURCE_REPO_URL="$CLAWORLD_CANONICAL_SOURCE_REPO"

export CLAWORLD_CANONICAL_SOURCE_REF="$(
  resolve_env_or_legacy "CLAWORLD_CANONICAL_SOURCE_REF" "CLAWORLD_SOURCE_REF" "$(resolve_source_ref)"
)"
export CLAWORLD_SOURCE_REF="$CLAWORLD_CANONICAL_SOURCE_REF"

if [[ -z "${CLAWORLD_PUSH_REPO_URL:-}" ]]; then
  if PUSH_REPO_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)"; then
    export CLAWORLD_PUSH_REPO_URL="$(normalize_github_push_url "$PUSH_REPO_URL")"
  else
    export CLAWORLD_PUSH_REPO_URL="git@github.com:Lightningxxl/claworld.git"
  fi
fi

export CLAWORLD_REFRESH_CANONICAL_SOURCE_ON_START="$(
  resolve_env_or_legacy "CLAWORLD_REFRESH_CANONICAL_SOURCE_ON_START" "CLAWORLD_SYNC_REMOTE_ON_START" "1"
)"
export CLAWORLD_SYNC_REMOTE_ON_START="$CLAWORLD_REFRESH_CANONICAL_SOURCE_ON_START"

export CLAWORLD_ALLOW_STALE_CANONICAL_SOURCE_ON_START="$(
  resolve_env_or_legacy "CLAWORLD_ALLOW_STALE_CANONICAL_SOURCE_ON_START" "CLAWORLD_ALLOW_STALE_SOURCE_ON_START" "0"
)"
export CLAWORLD_ALLOW_STALE_SOURCE_ON_START="$CLAWORLD_ALLOW_STALE_CANONICAL_SOURCE_ON_START"

if [[ "$CLAWORLD_CANONICAL_SOURCE_REPO" == "$REPO_ROOT" ]] && \
   [[ "$CLAWORLD_CANONICAL_SOURCE_REF" == origin/* ]] && \
   [[ "${CLAWORLD_REFRESH_CANONICAL_SOURCE_ON_START}" != "0" ]] && \
   git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
  if ! GIT_TERMINAL_PROMPT=0 git -C "$REPO_ROOT" fetch --prune origin; then
    if [[ "${CLAWORLD_ALLOW_STALE_CANONICAL_SOURCE_ON_START}" == "1" ]]; then
      echo "warning: failed to fetch origin for canonical source repo; continuing with existing refs"
    else
      echo "error: failed to refresh origin for canonical source repo"
      echo "hint: fix GitHub connectivity/auth, or set CLAWORLD_ALLOW_STALE_CANONICAL_SOURCE_ON_START=1 to continue with stale refs."
      exit 1
    fi
  fi
fi

mkdir -p "$SYMPHONY_WORKSPACE_ROOT"

echo "Starting Symphony for Claworld:"
echo "  workflow: $WORKFLOW_PATH"
echo "  canonical source repo: $CLAWORLD_CANONICAL_SOURCE_REPO"
echo "  canonical source ref: $CLAWORLD_CANONICAL_SOURCE_REF"
echo "  push repo: ${CLAWORLD_PUSH_REPO_URL:-unset}"
echo "  allow stale canonical source: ${CLAWORLD_ALLOW_STALE_CANONICAL_SOURCE_ON_START}"
echo "  workspaces: $SYMPHONY_WORKSPACE_ROOT"
echo "  openclaw ref: $OPENCLAW_REF_ROOT"
echo "  clawdbot-feishu ref: $CLAWDBOT_FEISHU_REF_ROOT"

exec "$ROOT_DIR/scripts/option2-run.sh" "$WORKFLOW_PATH"
