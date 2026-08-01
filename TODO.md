# j-workflow TODO

This file is the short operational backlog for future agents. Historical notes remain in `docs/multi-agent-workflow-optimizations/README.md`; use this file first when deciding what still needs work.

## Active Plan

- `docs/plans/refactor-and-manifest-migration.md` WP0-WP12 are complete. No active high-priority refactor work remains; use this file only for new prioritized follow-ups.

## Always-On Invariants

- Keep `/jflow`, root `workflow.json`, workspace run `workflow.json`, `workflow-state.json`, `orchestrate.sh`, and `bin/*` contracts aligned. When one changes artifact names, phase names, execution order, verdicts, or validation rules, update the others in the same change.
- Keep `design/plan.md` as the only final/latest plan filename. Do not introduce `final-plan.md`, `plan-final.md`, `plan-fix-rN.md`, or `fix-design.md`.
- Maintain `bin/validate-workspace-artifacts` as the workspace-level gate for artifact names, latest pointers, round continuity, and state phase names.
- Interactive phase completion is tracked through `workflow-state.json`; do not reintroduce `.done` files as phase completion markers. Started markers are only for Ghostty launch verification.

## Open Work

- None currently prioritized.

## Validation Checklist

- `bash -n orchestrate.sh`
- `python3 -m py_compile bin/*` for Python helpers
- `bin/validate-workflow-manifest workflow.json`
- `bin/create-workflow-run --template workflow.json --output <workspace>/workflow.json ...`
- `bin/validate-workspace-artifacts --manifest workflow.json --workspace <workspace>` on representative workspaces
- `git diff --check`
