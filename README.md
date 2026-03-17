# Symphony (Practical Repo Guide)

Symphony is an orchestrator that watches a Linear project, creates isolated workspaces per issue,
and runs Codex agents to implement work automatically.

This repository already includes the official Elixir reference implementation (`elixir/`) plus local
helper scripts so you can run quickly.

> Warning
> This is an experimental reference implementation. Use it in trusted environments only.

## What This Repo Can Do

- Poll Linear issues from one configured project.
- Start Codex app-server agents for active issues.
- Keep issue work running in isolated workspaces.
- Stop/cleanup work when issue reaches terminal states.

## Quick Start (Fastest Path)

1. Install runtime and build once:

```bash
cd /Users/lightningmb/Projects/symphony
./scripts/option2-setup.sh
```

2. Start service:

```bash
./scripts/option2-run.sh
```

If everything is healthy, you will see a `SYMPHONY STATUS` dashboard in terminal.

## Recommended Project-Owned Workflow Mode

For real project work, prefer running Symphony against the target repo's own
`WORKFLOW.md` instead of editing `symphony/elixir/WORKFLOW.md`.

For Claworld, use:

```bash
export LINEAR_API_KEY='your-linear-token'
export LINEAR_PROJECT_SLUG_ID='b6cad86a7c54'
cd /Users/lightningmb/Projects/symphony
./scripts/run-claworld.sh
```

For Claworld, treat `./scripts/run-claworld.sh` as the only supported launcher.
It resolves a canonical local mirror, optionally refreshes its remote-tracking refs with a
non-destructive `git fetch`, exports an explicit `CLAWORLD_CANONICAL_SOURCE_REF`, and then hands
control to Symphony. Do not run
`./scripts/option2-run.sh /Users/lightningmb/Projects/claworld/WORKFLOW.md` directly unless you are
also setting the Claworld-specific bootstrap env vars yourself.

Default assumptions in `scripts/run-claworld.sh`:

- Claworld repo: `~/Projects/claworld`
- Claworld canonical source ref: `origin/HEAD` when available, otherwise `origin/main`, then local `HEAD`
- Symphony workspaces: `~/Projects/claworld-workspaces`
- OpenClaw reference repo: `~/Projects/openclaw`
- Feishu reference repo: `~/Projects/clawdbot-feishu` or `~/Projects/clawbot-feishu`

Override them with env vars when needed:

```bash
CLAWORLD_ROOT=/abs/path/to/claworld \
SYMPHONY_WORKSPACE_ROOT=/abs/path/to/workspaces \
OPENCLAW_REF_ROOT=/abs/path/to/openclaw \
CLAWDBOT_FEISHU_REF_ROOT=/abs/path/to/clawdbot-feishu \
./scripts/run-claworld.sh
```

Optional Git bootstrap overrides:

```bash
CLAWORLD_CANONICAL_SOURCE_REPO=/abs/path/to/canonical/claworld \
CLAWORLD_CANONICAL_SOURCE_REF=origin/main \
CLAWORLD_PUSH_REPO_URL=git@github.com:Lightningxxl/claworld.git \
CLAWORLD_REFRESH_CANONICAL_SOURCE_ON_START=1 \
CLAWORLD_ALLOW_STALE_CANONICAL_SOURCE_ON_START=0 \
./scripts/run-claworld.sh
```

Legacy aliases still work for compatibility:

- `CLAWORLD_SOURCE_REPO_URL`
- `CLAWORLD_SOURCE_REF`
- `CLAWORLD_SYNC_REMOTE_ON_START`
- `CLAWORLD_ALLOW_STALE_SOURCE_ON_START`

This is the preferred harness-engineering setup because:

- the target repo owns its own repo map, workflow, and validation rules
- Symphony stays focused on orchestration, workspace lifecycle, and Linear polling
- project-specific context and acceptance harnesses evolve with the project instead
  of drifting inside the Symphony repo

## Current Local State (Important)

Treat `elixir/WORKFLOW.md` as a reference workflow for Symphony itself, not as the
authoritative Claworld runtime contract. For Claworld development, the source of truth is:

- `scripts/run-claworld.sh` for launcher/bootstrap policy
- `~/Projects/claworld/WORKFLOW.md` for project-owned workspace/bootstrap rules
- `~/Projects/claworld/docs/SYMPHONY_HARNESS.md` for harness expectations

The practical consequence is:

- `~/Projects/claworld` acts as the canonical local mirror
- launcher startup refreshes that mirror from `origin` once before scheduling begins
- Claworld workspaces are bootstrapped from an explicit canonical source repo and canonical source ref
- Claworld retries should reuse the existing workspace instead of auto-pulling remote state
- any remote sync should happen once at launcher time via `git fetch`, not as an implicit
  `git pull` before every retry

## Recommended Security Mode

Recommended approach:

1. Put token in env var.
2. Keep `WORKFLOW.md` as `api_key: $LINEAR_API_KEY`.
3. Keep the active Linear project binding as `project_slug: $LINEAR_PROJECT_SLUG_ID`.

Example:

```bash
export LINEAR_API_KEY='your_new_token'
export LINEAR_PROJECT_SLUG_ID='b6cad86a7c54'
./scripts/option2-run.sh
```

If your token was shared in chat or committed, rotate it in Linear immediately.

## How `WORKFLOW.md` Works

`elixir/WORKFLOW.md` has two parts:

1. YAML front matter: runtime configuration.
2. Markdown body: prompt template sent to each agent.

### Key YAML Fields

- `tracker.kind`
  - Task source type. In this repo the production path is `linear`.
- `tracker.api_key`
  - Linear personal API token (or `$LINEAR_API_KEY`).
- `tracker.project_slug`
  - Linear project identifier (slugId used by this implementation, often
    referenced as `$LINEAR_PROJECT_SLUG_ID`).
- `tracker.active_states`
  - Issue states that should keep being processed.
- `tracker.terminal_states`
  - Issue states that should stop and cleanup.
- `polling.interval_ms`
  - Poll interval for fetching candidate issues.
- `workspace.root`
  - Root folder where issue-specific workspaces are created.
- `hooks.after_create`
  - Commands run right after creating workspace.
- `hooks.before_remove`
  - Commands run before removing workspace.
- `agent.max_concurrent_agents`
  - Max parallel issues processed.
- `agent.max_turns`
  - Max continuous Codex turns per scheduling cycle.
- `codex.command`
  - Command used to start Codex app-server.
- `codex.approval_policy`, `thread_sandbox`, `turn_sandbox_policy`
  - Agent execution safety/permission controls.

## Helper Scripts in This Repo

- `scripts/option2-setup.sh`
  - Runs: `mise trust`, `mise install`, `mix setup`, `mix build`.
- `scripts/option2-run.sh`
  - Runs built Symphony with required confirmation flag:
  - `--i-understand-that-this-will-be-running-without-the-usual-guardrails`
  - Optional arg: custom workflow file path.

Examples:

```bash
./scripts/option2-run.sh
./scripts/option2-run.sh /absolute/path/to/WORKFLOW.md
```

## Typical Run Lifecycle

1. Orchestrator polls Linear project.
2. Finds active issues.
3. Creates workspace for an issue.
4. Executes `hooks.after_create`.
5. Launches Codex app-server and sends workflow prompt.
6. Agent iterates on issue until done, blocked, or state changes.
7. On terminal state, process is stopped and workspace cleanup runs.

## Troubleshooting

### 1) `LINEAR_API_KEY is not set`

- If token is in env mode: `export LINEAR_API_KEY='...'`
- If token is hardcoded in workflow: ensure `tracker.api_key` is non-empty.

### 2) `missing_linear_project_slug` or no issues picked up

- If project is in env mode: `export LINEAR_PROJECT_SLUG_ID='...'`
- Verify `tracker.project_slug` is correct.
- Verify issue states in Linear match `active_states`.

### 3) `mise ... not trusted`

Run:

```bash
cd /Users/lightningmb/Projects/symphony/elixir
mise trust
```

### 4) Service starts but does nothing

- Confirm project really has issues in active states.
- Confirm token has permission to read that project.

### 5) Start blocked by warning banner

Use the run script (`./scripts/option2-run.sh`), which already includes the required acknowledgement flag.

## Repo Structure

- `elixir/`: official reference implementation (runtime, scheduler, tracker adapter).
- `scripts/`: local helper scripts for setup/run.
- `.codex/`: optional Codex skills used by workflow.
- `SPEC.md`: architecture and behavior spec.

## References

- Root overview: `README.md` (this file)
- Elixir implementation details: `elixir/README.md`
- System spec: `SPEC.md`

## License

Apache-2.0. See `LICENSE`.
