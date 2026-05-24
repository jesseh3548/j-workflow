# Multi-Agent Development Orchestrator

多 Agent 协同开发编排器。通过独立 Claude session 做阶段隔离和交叉验证，降低单 agent 的上下文漂移和自检盲区。

## Contents

- [Overview](#overview)
- [Workflow](#workflow)
- [Quick Start](#quick-start)
- [Repository Layout](#repository-layout)
- [Phase Output Contract](#phase-output-contract)
- [Built-in Skills](#built-in-skills)
- [Config Example](#config-example)
- [Changelog and Backlog](#changelog-and-backlog)

## Overview

- Runtime: Claude Code + Ghostty (AppleScript tab API)
- Orchestrator entry: `workflow/SKILL.md` and `orchestrate.sh`
- Review loops:
  - `review-plan -> revise -> review-plan` until `VERDICT: PASS`
  - `review-code -> fix -> review-code` until `VERDICT: PASS`

## Workflow

```text
Phase 0.5  /review-requirement -> requirement-review/requirement-review.md
Phase 1    /explore            -> explore/exploration.md (optional)
Phase 2    /design             -> design/plan.md
Phase 3    /review-plan        -> review/review.md
Phase 3.5  revise              -> design/plan-rN.md + review/revise-notes-rN.md
Phase 4    /implement          -> implement/impl-notes.md
Phase 5    /review-code        -> review-code/code-review.md
Phase 5.5  fix                 -> review-code/fix-notes-rN.md
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

Or use the workflow skill in Claude Code:

```text
/workflow 帮我做卡交易对账功能，需求文档在 ~/docs/req.md，项目是 card-center
```

## Repository Layout

```text
.
├── orchestrate.sh
├── workflow-config.example.yaml
├── README.md
├── CHANGELOG.md
├── docs/
│   └── multi-agent-workflow-optimizations/
│       └── README.md
├── workflow/
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

## Built-in Skills

- `/review-requirement`
- `/explore`
- `/design`
- `/review-plan`
- `/implement`
- `/review-code`
- `/verify-observability`
- `/workflow`

## Config Example

See [`workflow-config.example.yaml`](./workflow-config.example.yaml).

## Changelog and Backlog

- Change history: [`CHANGELOG.md`](./CHANGELOG.md)
- Optimization backlog: [`docs/multi-agent-workflow-optimizations/README.md`](./docs/multi-agent-workflow-optimizations/README.md)

## Notes

- Ghostty 1.3.0+ is required for AppleScript tab orchestration.
- `orchestrate.sh` is the shell entry and stays in sync with the workflow skill.
