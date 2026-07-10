# j-workflow TODO

This file is the short operational backlog for future agents. Historical notes remain in `docs/multi-agent-workflow-optimizations/README.md`; use this file first when deciding what still needs work.

## Active Plan

- Execute `docs/plans/refactor-and-manifest-migration.md` (WP1-WP12): bug fixes, shared capabilities, full manifest-driven migration of `orchestrate.sh`, and the `/workflow` → `/jflow` rename. Follow its ordering and acceptance criteria; mark WPs done in that file.

## High Priority

- Keep `/workflow`, root `workflow.json`, workspace run `workflow.json`, `workflow-state.json`, `orchestrate.sh`, and `bin/*` contracts aligned. When one changes artifact names, phase names, execution order, verdicts, or validation rules, update the others in the same change.
- Keep `design/plan.md` as the only final/latest plan filename. Do not introduce `final-plan.md`, `plan-final.md`, `plan-fix-rN.md`, or `fix-design.md`.
- Maintain `bin/validate-workspace-artifacts` as the workspace-level gate for artifact names, latest pointers, round continuity, and state phase names.
- `review-requirement` and `verify-observability` will be added to `orchestrate.sh` as part of the manifest migration (WP9 in `docs/plans/refactor-and-manifest-migration.md`), after the generic phase engine (WP8) lands. Do not add them ad hoc before that.

## Medium Priority

- Move more phase execution policy from `orchestrate.sh` into workspace `workflow.json` when it reduces duplication without hiding control flow. Root `workflow.json` is the template; each run should execute against `<workspace>/workflow.json`.
- Improve resume from `workflow-state.json`: use `current_loop`, `current_round`, `current_phase`, `last_finished_phase`, and `artifact_validation_status` to produce clearer recovery decisions.
- Further shorten `workflow/SKILL.md` by replacing duplicated phase contract text with manifest/helper references where practical.

## Validation Checklist

- `bash -n orchestrate.sh`
- `python3 -m py_compile bin/*` for Python helpers
- `bin/validate-workflow-manifest workflow.json`
- `bin/create-workflow-run --template workflow.json --output <workspace>/workflow.json ...`
- `bin/validate-workspace-artifacts --manifest workflow.json --workspace <workspace>` on representative workspaces
- `git diff --check`
