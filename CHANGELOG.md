# Changelog

## Unreleased

- Make `--resume` state-driven: phases skip only when state, output file, and artifact validation all pass; startup artifact validation is warning-only in resume mode, and review/fix loops can continue from the pending revise/fix round (WP6 in `docs/plans/refactor-and-manifest-migration.md`).
- Add periodic wait hints and optional `--phase-timeout` / `phase_timeout` for interactive phases so a stuck agent can be manually unlocked or marked failed (WP5 in `docs/plans/refactor-and-manifest-migration.md`).
- Add shared `bin/archive-workspace` and call it before non-resume runs so existing workspace artifacts are archived to `archive/round-N/` instead of being overwritten (WP4 in `docs/plans/refactor-and-manifest-migration.md`).
- Stop hardcoding Claude's default model in `orchestrate.sh`; when no model is specified, Claude uses its CLI default and workflow state records `provider-default` (WP12 in `docs/plans/refactor-and-manifest-migration.md`).
- Replace ambiguous breakpoint `s=skip next phase` handling with explicit `a=accept current result` choices per breakpoint and a uniform `q` resume-safe exit (WP3 in `docs/plans/refactor-and-manifest-migration.md`).
- Add `--max-rounds` / `max_rounds` to cap review/revise and review-code/fix loops, exiting safely in `--auto` mode when a loop is exhausted (WP2 in `docs/plans/refactor-and-manifest-migration.md`).
- Fix config precedence so explicit CLI flags override values loaded from `.workflow-config.yaml` (WP1 in `docs/plans/refactor-and-manifest-migration.md`).
- Fix `parse_config` not stripping inline `#` comments, which made the shipped `workflow-config.example.yaml` silently disable all phase toggles and breakpoints (WP0 in `docs/plans/refactor-and-manifest-migration.md`).
- Add `docs/plans/refactor-and-manifest-migration.md`: executable work packages for bug fixes (CLI-over-config precedence, review-loop round caps, breakpoint semantics), shared capabilities (workspace archiving, poll-timeout hints, state-driven resume), full manifest-driven migration of `orchestrate.sh`, and the `/workflow` → `/jflow` skill rename.
- Fix Ghostty phase run scripts failing with `claude: command not found` / `codex: command not found` when the CLI executable is not available in the non-interactive shell PATH. The orchestrator now resolves Claude Code/Codex to an absolute executable path up front and writes that path into generated run scripts.
- Add `CLAUDE_BIN` / `CODEX_BIN` override support for non-standard CLI install locations.
- Start Ghostty phases through a temporary no-space launcher script instead of `bash <run_script>`, avoiding Chinese IME conversion of `bash` and Ghostty command argument parsing failures.
- Rework the `review-code` skill to expand review context beyond changed hunks, report callers/callees/tests/config coverage, and keep review separate from code fixing.
- Restructure `review-code` rules into an Alibaba Java Coding Guidelines-style hierarchy with a routing index and focused rule files for programming, exception/logging, MySQL, project, security, testing, performance, and observability reviews.
- Add `design/implementation-brief.md` as a plan-derived implementation checklist / trace index and pass it through implement, review-code, and fix prompts so new sessions can verify completeness without treating the brief as a second source of truth.
- Add review-code context budget rules: hunk-first diff reading, staged/unstaged coverage, and bounded line-window reads for large source files.
- Update `/workflow` skill execution flow so pure analysis phases run as bounded subagent phases, while explore/design/revise/implement/fix remain Ghostty interactive phases.
- Strengthen design/review-plan/implement contracts: plan.md is the single source of truth, implementation-brief is only a plan-derived checklist, review-plan verifies hidden assumptions, and workflow performs lightweight artifact quality checks.
- Clarify provider-native capabilities: `/explore` no longer forces Claude's native Explore subagent, and Claude Code dynamic workflow is documented as separate from j-workflow orchestration.
- Add phase-specific model overrides for the shell orchestrator and config file, including design/review/implement/review-code/fix model selection.
- Add `workflow.json` as the default declarative phase manifest and record the selected flow file in `workflow-state.json` metadata.
- Split orchestration helpers into `bin/` scripts: manifest access, artifact validation, workflow-state validation, Ghostty window detection, phase run-script rendering, and non-interactive provider execution now live outside `orchestrate.sh`.
- Drive review/revise and review-code/fix loop transitions from `workflow.json` verdict mappings, and persist loop metadata (`round`, `loop`, `transition`, `resume_from`, `current_phase`, `last_finished_phase`, `ghostty_window_id`) in `workflow-state.json`.
- Add `--skip-git-repo-check` to the Codex non-interactive runner so analysis phases can run in temporary validation/workspace directories.
- Require review-code/fix/manual CR decisions to synchronize final facts back into `design/plan.md`, and into `design/implementation-brief.md` when checklist content changes.
- Clarify that `design/plan.md` is the only final/latest plan filename; fix/manual CR updates modify it directly instead of creating additional final-plan variants.
- Align `/workflow` artifact validation docs with `workflow.json` for Plan/Brief synchronization fields, while leaving `review-requirement` and `verify-observability` out of the shell entry for now.
- Add `bin/validate-workspace-artifacts` and call it from `orchestrate.sh` to enforce workspace artifact names, latest pointers, contiguous review/fix rounds, forbidden plan variants, and manifest-compatible state phase names.
- Add `TODO.md` as the short current backlog so future agents do not need to infer active work from historical optimization notes.
- Replace interactive phase `.done` marker files with `workflow-state.json` phase status as the single completion signal; run scripts now only use workflow state for user-confirmed completion and exit-code fallback.
- Add `bin/create-workflow-run` and generate `<workspace>/workflow.json` for each run from the repository workflow template; `orchestrate.sh` records the workspace workflow in state and uses its `execution.order` to set shell phase switches.

## v2.3 — 2026-05-17

### Skill 调用重构（消除 prompt 重复）

将 workflow 各 Phase 的内联 prompt 替换为 standalone skill 调用：

| Phase | 改动 |
|-------|------|
| 0.5 Review Requirement | 内联 20 行 → `调用 /review-requirement skill` |
| 1 Explore | 内联 15 行 → `调用 /explore skill` |
| 2 Design | 内联 25 行 → `调用 /design skill` |
| 3 Review Plan | 内联 22 行 → `调用 /review-plan skill` |
| 4 Implement | 内联 55 行 → `调用 /implement skill` |
| 5 Review Code | 内联 30 行 → `调用 /review-code skill` |
| 5.2 Verify Observability | 内联 18 行 → `调用 /verify-observability skill` |

未改动：Phase 3.5 Revise、Phase 5.5 Fix（session 续接，无独立 skill）

**效果**：workflow SKILL.md 从 724 行降至 ~570 行。修改 skill 后所有入口（standalone + workflow）自动同步。

### 决策落地规则

解决跨 agent 信息丢失问题：agent 和用户对话中达成的决策必须写入产出文件，下游 agent 只读文件。

| Agent | 落地位置 |
|-------|---------|
| Explore | exploration.md 末尾「决策记录」章节 |
| Design | plan.md 对应章节 + 末尾「设计决策记录」 |
| Implement | impl-notes.md「实现决策记录」 |
| Revise | revise-notes-rN.md 中记录讨论决策 |
| Fix | fix-notes-rN.md 未修复理由含讨论决策 |

### Review-Code 分层加载

将 review-code skill 从 492 行全量加载拆为按需加载：

```
~/.claude/skills/review-code/
├── SKILL.md          # 148 行：流程框架 + 维度路由表
└── rules/            # 16 个文件，共 267 行
    ├── naming.md
    ├── format.md
    ├── oop.md        # 含 null 判断规则（StringUtils/CollectionUtils）
    ├── collection.md
    ├── concurrency.md
    ├── flow-control.md
    ├── comments.md
    ├── misc.md
    ├── exception.md
    ├── logging.md
    ├── database.md
    ├── testing.md
    ├── performance.md
    ├── observability.md
    ├── security.md
    └── engineering.md
```

Agent 根据 diff 涉及的内容只读取相关维度的规则文件，初始 context 占用降 70%。

### 新增编码规则

- `rules/programming/oop.md`：禁止对 String 裸判 `!= null`，应用 `StringUtils.isBlank/isNotBlank`；Collection 用 `CollectionUtils.isEmpty`；通用对象用 `Objects.nonNull` 或 Optional

### Backlog 新增

- #26 需求变更重入质量下降（高优）— 6 个可能原因 + 4 个解法方向
- #27 轻量修复 agent/patch（中优）— 处理测试问题和人工 CR 建议

---

## v2.2 — 2026-05-04（上次变更）

- 决策确认规则（🔀 格式）加入 design/implement/revise/fix
- 增量覆盖率 ≥70% 加入 implement skill
- 测试执行改为 `mvn test -pl <模块> -Dtest=<类>`
- verify-observability skill 完成（backlog #19）
- OMH 对比分析完成，backlog #20-25 录入

---

See optimization backlog: [`docs/multi-agent-workflow-optimizations/README.md`](./docs/multi-agent-workflow-optimizations/README.md)
