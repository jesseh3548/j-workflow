# j-workflow

Multi-Agent Development Orchestrator for Claude Code and Codex.

多 Agent 协同开发编排器。通过独立 agent session 做阶段隔离和交叉验证，降低单 agent 的上下文漂移和自检盲区。

## Contents

- [Overview](#overview)
- [Workflow](#workflow)
- [Quick Start](#quick-start)
- [Repository Layout](#repository-layout)
- [Phase Output Contract](#phase-output-contract)
- [Built-in Skills](#built-in-skills)
- [Config Example](#config-example)
- [Claude Code and Codex Support](#claude-code-and-codex-support)
- [Changelog and Backlog](#changelog-and-backlog)

## Overview

- Runtime: Claude Code or Codex + Ghostty (AppleScript tab API)
- Orchestrator entry: `jflow/SKILL.md` and `orchestrate.sh`
- Flow manifest: repository `workflow.json` is the default phase manifest/template. Each run generates `<workspace>/workflow.json` with `kind: "run"` and `execution.order`; `workflow-state.json` records actual runtime state and points to that workspace workflow.
- Execution contract: the run workflow records the actual phase order for this task. `orchestrate.sh` generates it from CLI/config flags, then runs a generic phase engine over `execution.order`; review/revise and review-code/fix loops are driven by manifest loop metadata and verdict transitions.
- Shared utilities: script capabilities live in `bin/`; `orchestrate.sh` calls them and keeps orchestration logic thin: `bin/ghostty-open-tab`, `bin/detect-ghostty-window`, `bin/archive-workspace`, `bin/create-workflow-run`, `bin/workflow-state`, `bin/workflow-manifest`, `bin/list-claude-models`, `bin/find-agent-session`, `bin/validate-workflow-manifest`, `bin/validate-workflow-state`, `bin/validate-artifact`, `bin/validate-workspace-artifacts`, `bin/render-prompt`, `bin/render-phase-run-script`, `bin/run-provider-noninteractive`
- Runner modes:
  - `/jflow` uses bounded subagent phases for pure analysis/review/verification work when the provider exposes an Agent tool.
  - Interactive phases use Ghostty tabs for long-lived sessions and user confirmation.
  - `orchestrate.sh` can run pure analysis phases through non-interactive Claude/Codex CLI execution as a shell-compatible path.
- Review loops:
  - `review-plan -> revise -> review-plan` until `VERDICT: PASS`
  - `review-code -> fix -> review-code` until `VERDICT: PASS`
- Final source of truth: `design/plan.md` must remain complete and accurate at the end of the workflow. It is the only final plan filename; do not create `final-plan.md` or `plan-fix-rN.md`. Decisions from user discussion, manual CR feedback, review-code, or fix must be synchronized back into `plan.md`; update `design/implementation-brief.md` when the implementation checklist changes.
- Workspace artifact gate: `bin/validate-workspace-artifacts` enforces allowed artifact names, round continuity, latest pointer consistency, and forbidden final-plan variants.
- Shell entry: `orchestrate.sh` and `/jflow` share the same manifest phase order; CLI/config flags only enable, disable, or break phases for a specific run.
- Isolation requirement: prefer an independent subagent or independent Ghostty session for each phase. If a provider does not expose an Agent tool for pure analysis phases, keep the fallback bounded by the same output, VERDICT, and write-scope contract.

## Workflow

```text
Phase 0.5  /review-requirement -> requirement-review/requirement-review.md (subagent phase)
Phase 1    /explore            -> explore/exploration.md (optional, interactive)
Phase 2    /design             -> design/plan.md (interactive)
Phase 3    /review-plan        -> review/review.md (subagent phase)
Phase 3.5  revise              -> design/plan-rN.md + review/revise-notes-rN.md
Phase 4    /implement          -> implement/impl-notes.md (interactive)
Phase 5    /review-code        -> review-code/code-review.md (subagent phase)
Phase 5.5  fix                 -> review-code/fix-notes-rN.md
Phase 6    /verify-observability -> verify-observability/observability-report.md (subagent phase)
```

## Quick Start

```bash
# interactive mode
./orchestrate.sh --project ~/code/card-center --name "卡对账" --requirement ~/docs/req.md

# enable explore phase
./orchestrate.sh --project ~/code/card-center --name "卡对账" --explore --idea "卡交易自动对账" --requirement ~/docs/req.md

# auto mode
./orchestrate.sh --project ~/code/card-center --name "卡对账" --requirement ~/docs/req.md --auto
```

Or use the jflow skill in a supported agent CLI:

```text
/jflow 帮我做卡交易对账功能，需求文档在 ~/docs/req.md，项目是 card-center
```

## Repository Layout

```text
.
├── orchestrate.sh
├── workflow.json
├── workflow-config.example.yaml
├── prompts/
├── bin/
├── README.md
├── CHANGELOG.md
├── docs/
│   └── multi-agent-workflow-optimizations/
│       └── README.md
├── jflow/
├── review-requirement/
├── explore/
├── design/
├── review-plan/
├── implement/
├── review-code/
└── verify-observability/
```

## Phase Output Contract

| Path | Source | Description |
| --- | --- | --- |
| `requirement.md` | input | requirement document |
| `requirement-review/requirement-review.md` | phase 0.5 | requirement review report |
| `explore/exploration.md` | phase 1 | current system exploration |
| `design/plan.md` | phase 2/3.5 | latest design plan |
| `review/review.md` | phase 3 | latest plan review report |
| `implement/impl-notes.md` | phase 4 | implementation notes |
| `review-code/code-review.md` | phase 5 | latest code review report |
| `verify-observability/observability-report.md` | phase 6 | observability verification report |

## Built-in Skills

- `/review-requirement`
- `/explore`
- `/design`
- `/review-plan`
- `/implement`
- `/review-code`
- `/verify-observability`
- `/jflow`

## Config Example

See [`workflow-config.example.yaml`](./workflow-config.example.yaml).

Configuration precedence is: CLI flags > config file > built-in defaults.

## Claude Code and Codex Support

Provider support:

- Use `--provider claude|codex` to select the agent CLI used for phase sessions.
- During each new `/jflow` initialization, Claude choices are fetched fresh from the configured gateway `/v1/models` endpoint by `bin/list-claude-models`. Results are grouped into Opus/Sonnet/Haiku, version-descending, with `us.` routes preferred for equivalent versions; no catalog is cached or hard-coded.
- Use `--model <model>` to select the model for either provider. `/jflow` writes the selected Claude model ID into the workspace run `workflow.json`; the standalone shell entry still uses Claude CLI configuration when `--model` is omitted. Codex defaults to the model in `~/.codex/config.toml`.
- Use phase-specific model overrides when needed: `--model-explore`, `--model-design`, `--model-review`/`--model-review-plan`, `--model-revise`, `--model-implement`, `--model-review-code`, and `--model-fix`. Unspecified phases inherit `--model`.
- Use `--max-rounds <n>` to cap review/revise and review-code/fix loops. The default is `3`; `--auto` exits with code `2` when a loop is exhausted.
- Use `--phase-timeout <minutes>` to fail either an interactive wait or a non-interactive provider run after a bounded time. The default is `0`, meaning no timeout; the selected value is persisted into the run workflow and reused by `--resume`.
- Use `--flow <file>` to select the source workflow template. The orchestrator writes the task-specific run workflow to `<workspace>/workflow.json` and records that path in `workflow-state.json`.
- `workflow-state.json` is a runtime snapshot. It records the current main orchestrator agent (`main_agent.provider` / `main_agent.session_id`), selected run workflow metadata, current/last phase cursors, Ghostty window id, per-phase status, session id, loop, round, transition, prompt path, run script path, and output path.
- `--resume` restores `provider` and `model` from the workspace run `workflow.json` without refreshing or reopening model selection, then prints a state summary including current phase, last finished phase, current loop/round, artifact validation status, and any exhausted loop marker.
- The orchestrator resolves the selected CLI to an absolute path before opening Ghostty tabs. If the CLI is not in a non-interactive shell PATH, set `CLAUDE_BIN` or `CODEX_BIN` to the executable path.
- Support only Claude Code and Codex initially.
- Keep Ghostty tab orchestration as the session isolation boundary.
- Track phase status and session IDs in `workflow-state.json`.
- Preserve native resume semantics for each provider: Claude Code uses session IDs, Codex uses `codex resume <session_id>`.
- Resume policy: revise resumes the stored design `session_id`; fix resumes the stored implement `session_id`. If the ID is missing, Claude may fall back to session name, but Codex requires a stored session ID.
- Avoid hard-coded Claude-only paths such as `~/.claude` in reusable skills.
- Keep `orchestrate.sh` as a standalone hard-flow driver; `/jflow` can reuse the same shared scripts.
- Keep phase skill frontmatter unchanged unless a provider requires a different skill manifest format.
- Use environment context only for default inference. Explicit `--provider` must always take precedence.

Claude Code note:

- Claude Code may show `Run a dynamic workflow?` for large implementation tasks. That is Claude Code's native dynamic workflow runtime, not this project's `/jflow` phase orchestration.
- Native dynamic workflow may be useful inside an implement phase after explicit user confirmation, but it does not replace j-workflow artifacts such as `design/plan.md`, `design/implementation-brief.md`, `implement/impl-notes.md`, or `review-code/code-review.md`.
- If native dynamic workflow reports `/login`, `401`, or `No api key passed in`, treat it as provider authentication for that native runtime and fall back to the normal implement flow.

## Changelog and Backlog

- Change history: [`CHANGELOG.md`](./CHANGELOG.md)
- Optimization backlog: [`docs/multi-agent-workflow-optimizations/README.md`](./docs/multi-agent-workflow-optimizations/README.md)

## Notes

- Ghostty 1.3.0+ is required for AppleScript tab orchestration.
- `orchestrate.sh` is the shell entry and stays in sync with the jflow skill.
- Repository rename does not automatically update installed runtime skills. Production `/jflow` must be synced as a runtime bundle: `SKILL.md`, `bin/`, `prompts/`, `workflow.json`, `orchestrate.sh`, and `workflow-config.example.yaml`.
