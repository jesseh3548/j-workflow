# Multi-Agent Workflow — Remaining Optimizations (Improvement Backlog)

Related:
- Main README: [`../../README.md`](../../README.md)
- Changelog: [`../../CHANGELOG.md`](../../CHANGELOG.md)
- Current short backlog: [`../../TODO.md`](../../TODO.md)

> This document keeps historical analysis and implementation notes. Check `TODO.md` first before treating older "仍需跟进" entries as current work.

## 管理规则

- 完成的 backlog 从「Backlog」移到「Already Done」表，保留编号和完成时间，不要直接删除
- 部分完成的标注"部分完成"并说明剩余部分

## Already Done

| # | Optimization | Status | Date |
|---|---|---|---|
| 1 | 评审反馈闭环 — review → revise 循环直到 VERDICT: PASS | **Done** | 2026-04-08 |
| 2 | 实现阶段上下文增强 — design 输出"实现指引"章节，implement 先读关键文件 | **Done** | 2026-04-08 |
| 3 | CLAUDE.md 注入检查 — orchestrate.sh 启动时检查并警告 | **Done** | 2026-04-08 |
| 5 | 断点续跑 — `--resume` 参数，检查产出文件跳过已完成阶段 | **Done** | 2026-04-13 |
| 8 | Ghostty 原生 AppleScript 集成 — 用 `new tab in window id` 在同一窗口开 tab | **Done** | 2026-04-13 |
| 11 | Alibaba Java 编码规范集成 — review-code 12 维度 Checklist + implement 编码规范摘要 | **Done** | 2026-04-15 |
| 12 | Code Review-Fix 循环 — implement → review-code → fix 反馈闭环，循环直到 PASS | **Done** | 2026-04-15 |
| 13 | 版本化产出文件 — review-rN.md / plan-rN.md / code-review-rN.md / fix-notes-rN.md | **Done** | 2026-04-15 |
| 14 | 需求审视 Agent — review-requirement skill，审视需求合理性（逻辑矛盾、边界模糊、可扩展性、外部知识验证） | **Done** | 2026-04-16 |
| 17 | Ghostty 新 Tab 输入法干扰修复 — run script 开头用 Swift/Carbon 切换到 ABC 输入源，零依赖 | **Done** | 2026-04-22 |
| 18 | Design Agent plan 修改规范 — 禁止追加式修改，强制就地编辑 + 全文一致性检查 + 修改后通读验证 | **Done** | 2026-04-22 |
| 19 | 可观测性验证 Agent — verify-observability skill，两步验证：静态代码检查 + MCP 运行时平台验证（日志/Metrics/告警） | **Done** | 2026-04-22 |

## Backlog

### 4. 按阶段指定模型（中优）

**Problem**: 所有阶段共用 `--model`，无法按阶段选择不同模型（如设计/评审用 opus，实现用 sonnet）。

**Fix**: 新增 `--model-<phase>` 参数覆盖特定阶段，未指定的继承 `--model` 全局默认。涉及阶段：explore、design、review、revise、implement、review-code。示例：
```bash
orchestrate.sh --project ~/code/xxx --requirement req.md \
  --model '<本次初始化实时选择的 Claude model ID>' \
  --model-design '<本次初始化实时选择的 Claude model ID>' \
  --model-review '<本次初始化实时选择的 Claude model ID>'
```
需改动：orchestrate.sh（参数解析 + run_phase 读取阶段模型）、jflow skill（支持生成新参数）、README。

**已完成（CLI/config，2026-07-08）**:
- `orchestrate.sh` 支持 `--model-explore`、`--model-design`、`--model-review` / `--model-review-plan`、`--model-revise`、`--model-implement`、`--model-review-code`、`--model-fix`。
- `.workflow-config.yaml` 支持 `model_explore`、`model_design`、`model_review_plan`、`model_revise`、`model_implement`、`model_review_code`、`model_fix`。
- 未指定阶段模型时继承全局 `--model` / `model`。

### 5. ~~错误恢复和断点续跑~~ → Done (2026-04-13)

已实现 `--resume` 参数。

### 8.5 Claude Session 断点续接 — 精确 resume（中优）

**Problem**: revise 用 `--resume <session-name>` 续接 design session，但多次测试后会产生多个同名 session，导致弹出交互式选择器而非自动续接。

**Fix**: 改用 session ID 精确续接。design 阶段结束后从 Claude Code 的 session 存储目录（默认 `~/.claude`，可通过 `CLAUDE_HOME` 覆盖）查找最新 session ID，写入 workflow state；revise 时读取并用 Claude Code `--resume <session_id>` 续接。注意：`--session-id <uuid>` 是指定当前 conversation ID，不是续接旧会话；用于续接会报 `Session ID ... is already in use`。

### 6. 产出质量自动校验（低优）

**Problem**: 每阶段只检查输出文件是否存在，不检查内容是否完整。plan.md 可能缺少"可观测性"章节但仍被认为"完成"。

**Fix**: 对 plan.md 和 review.md 做章节标题校验，缺少必需章节时警告或重跑。

**已完成（skill 规则 + 脚本级校验，2026-07-09）**:
- `/jflow` skill 增加轻量产物质量校验表。
- 覆盖 requirement-review、plan、implementation-brief、review、impl-notes、code-review、fix-notes、observability-report 的必需章节和 VERDICT。
- `bin/validate-artifact` 已提供脚本级产物校验，`orchestrate.sh` 只负责调用，避免 shell 入口只检查文件存在。
- 交互阶段 prompt 已要求：与用户交流后若最终结论/边界/取舍变化，必须先回写产出文档，再通过 `workflow-state.json` 写入完成状态。

### 9. 编排器迁入 Claude Code（高优）

**Problem**: 当前编排器是独立 shell 脚本 (`orchestrate.sh`)，入口在终端而非 Claude Code。用户需要离开 Claude Code 去终端执行命令，编排器的断点交互（`read`）也很原始，无法灵活调整参数、跳过阶段或与编排器对话。

**Fix**: 将编排逻辑从 `orchestrate.sh` 迁入 Claude Code skill（`/jflow` 或新 skill），用 Bash `run_in_background` 驱动：

1. Claude Code 做准备工作（理解需求、拉飞书文档、生成 requirement.md、确认参数）
2. 每个阶段：Bash `run_in_background` 开 Ghostty 新 tab + 轮询 `workflow-state.json`
3. Agent 在新 tab 里执行，用户在 tab 内和 agent 交互，确认后 agent 写 `workflow-state.json` phase status
4. 后台任务完成通知 Claude Code → Claude Code 在主对话中询问用户是否推进下一阶段
5. 用户确认 → 开下一阶段

**优势**：
- 入口统一在 Claude Code 中
- 每个阶段有两道确认：tab 内（agent 和用户交互）+ 主对话（编排器断点）
- 断点处可灵活对话（跳过、调参、查看产出、追问）
- 不再依赖 shell `read` 原始交互

**流程重入（需求变更场景）**：
- 支持从指定阶段重新开始（如"回到 design"）
- 重入时将该阶段及后续的旧产出归档到 `archive/round-N/`，不删除
- 新 agent 使用全新 session（旧 session 上下文会干扰），不复用
- 新 agent 的 prompt 中提供旧产出路径作为参考："需求已变更，旧方案在 archive/round-1/plan.md 可参考"
- revise 仍续接当轮的 design session（不是旧轮的）
- 介入方式：在当前 tab 里告诉 agent 停下（或 Ctrl+C），回到主对话说"需求改了，回到 design"

**涉及改动**：
- 新建或重构 `/jflow` skill 为编排器
- `open_ghostty_tab` + run script 生成逻辑迁入 skill
- 产出归档逻辑（`archive/round-N/`）
- `orchestrate.sh` 降级为可选的 CLI 入口（或废弃）
- 备份已保存：`backup-2026-04-14/`

### 7. 多项目/多模块支持 + Git Worktree 并行（未来）

**Problem**: 当前只支持单项目单模块串行。跨项目需求（如 card-center + card-transaction-service）无法在一次编排中处理；多模块实现只能串行，不能并行。

**Fix**:
- 支持 `--project` 多次传入，或用 `--add-dir` 补充关联项目目录
- 多模块并行实现时，每个 implement agent 使用独立的 git worktree，避免互相踩文件
- 各 worktree 在独立 branch 上工作，完成后 merge 回主分支
- design/review 阶段仍串行（主要是读代码写文档，不需要 worktree 隔离）

### 15. 飞书机器人通知 — 关键节点推送消息（高优）

**Problem**: Agent 完成某个阶段后，用户需要一直盯着终端等通知。如果用户在开会或做其他事，会错过"等待确认"的时间窗口，导致流程空转。

**Fix**: 在编排器的关键节点，通过飞书（Lark）自定义机器人 Webhook 发送通知给用户。

**通知节点**：
1. **需求审视完成** — 附 VERDICT，NEEDS_CLARIFICATION 时列出待确认项
2. **方案设计完成** — 提示用户去 tab 审阅
3. **方案评审完成** — 附 VERDICT（PASS / NEEDS_REVISION）
4. **实现完成** — 附测试通过/失败状态
5. **代码评审完成** — 附 VERDICT（PASS / NEEDS_FIX）
6. **全流程完成** — 汇总所有产出文件路径
7. **异常中断** — Agent session 异常退出时告警

**消息格式**：飞书富文本卡片，包含：
- 阶段名称 + 状态（通过/待确认/失败）
- 关键信息摘要（VERDICT、待确认项数量、测试结果）
- 产出文件路径
- 下一步操作提示

**实现方式**：
- 飞书自定义机器人 Webhook（最简单，不需要应用审批）
- 配置项：`LARK_WEBHOOK_URL`（环境变量或 `.workflow-config.yaml`）
- 可选：`LARK_WEBHOOK_SECRET`（签名校验）
- 编排器在每个阶段完成后调用 `curl` 发送 POST 请求
- 或封装为 `notify.sh` 脚本，支持不同消息模板

**涉及改动**：
- `orchestrate.sh` — 每个阶段完成后调用通知
- `jflow/SKILL.md` — 编排器在阶段间确认前发通知
- 新增 `bin/notify-lark.sh`（或内联到编排器），安装时同步到当前 provider 的工具目录
- 配置文件新增 `LARK_WEBHOOK_URL` 字段

### 16. 大 PRD 上下文溢出 — 需求文档预处理（高优）

**Problem**: 实际 PRD 文档可能非常大（如 107K），agent 一次性读入后 context 直接撑爆。影响 review-requirement（需要读全文找矛盾）、design（需要理解全部需求出方案）、review-plan（需要对照需求验证方案）。如果 design session 已经 context 满了，后续 revise 续接时也救不回来。

**影响面**：
- 直接受影响：review-requirement、design、review-plan
- 间接受影响：revise（续接 design session）、implement（plan.md 质量受连锁影响）
- 不受影响：review-code、fix（不读 PRD 原文）

**Fix（推荐分阶段实现）**：

**Phase 1（最小可用）：PRD 摘要预处理**
- 编排器在 Phase 0 准备 workspace 时，新增一步：用独立 agent 将大 PRD 压缩为结构化摘要
- 摘要格式固定：核心目标、功能清单（编号）、业务规则（按功能分组）、数据模型要求、非功能需求、约束与依赖
- 摘要写入 `requirement-summary.md`，原文保留为 `requirement-full.md`
- 后续 agent 默认读摘要，prompt 中注明"完整需求在 requirement-full.md，需要细节时按章节查阅"
- 阈值：requirement.md 超过 30K 字符时自动触发摘要，否则直接使用原文

**Phase 2（增强）：章节索引 + 按需引用**
- 摘要 agent 同时输出章节索引（章节标题 + 行号范围 + 一句话摘要）
- 后续 agent 需要细节时，通过 Read tool 的 offset/limit 精确读取对应章节
- 避免全量读入，最大化 context 利用率

**Phase 3（完善）：review-requirement 专用模式**
- review-requirement 需要原文才能找逻辑矛盾，但不需要一次读完
- 改为分章节审视：先读索引 → 逐章节读取并审视 → 最后汇总
- 或用 subagent 并行审视不同章节

**涉及改动**：
- `jflow/SKILL.md` — Phase 0 新增摘要步骤，各阶段 prompt 改为引用摘要
- `orchestrate.sh` — 同步新增摘要步骤
- 新增 `summarize-requirement/SKILL.md`（或内联到编排器），安装时同步到当前 provider 的 skills 目录
- 各阶段 prompt 中 `requirement.md` 引用改为 `requirement-summary.md` + 按需引用原文

### 10. 动态流编排 — 可组装的 Agent 流水线（未来）

**Problem**: 当前流程是硬编码的 `explore → design → review → revise → implement → review-code`，所有需求都走同一条路。但不同任务类型需要不同的流：bug fix 不需要 design，纯方案评审不需要 implement，复杂需求可能需要多轮并行 implement。

**Fix**: 将每个 agent 变成可插拔的步骤，主 agent（编排器）根据任务描述动态规划流程：
1. 用户描述任务 → 编排器分析任务类型
2. 编排器生成执行计划（哪些步骤、什么顺序、是否并行）
3. 展示计划给用户确认
4. 确认后按计划逐步执行

**示例场景**：
- 简单 bug fix → `implement → review-code`
- 纯方案评审 → `design → review`
- 复杂跨模块 → `explore → design → review → revise → implement×N (并行) → review-code`
- 线上排查 → `troubleshoot → hotfix implement → review-code`

**前置依赖**：每个 agent skill 需要标准化输入/输出接口，编排器才能自由组合。

### 20. 声明式 flow JSON（高优）

**Problem**: 流程定义硬编码在 SKILL.md 和 orchestrate.sh 中，修改流程需要改代码。阶段顺序、是否跳过、并行配置都散落在多个文件里，不直观。

**Fix**: 把流程定义抽到 `workflow.json`（或 YAML），格式参考 oh-my-harness 的声明式流水线：
```json
{
  "phases": [
    {"name": "review-requirement", "model": "opus", "confirm": "required"},
    {"name": "design", "model": "opus", "confirm": "auto"},
    {"name": "review-plan", "model": "opus", "confirm": "required"},
    {"name": "implement", "model": "sonnet", "parallel": false},
    {"name": "review-code", "model": "opus", "confirm": "required"}
  ]
}
```
编排器读 JSON 驱动执行，不再硬编码阶段列表。

**涉及改动**：
- 新增 `workflow.json` 模板
- `orchestrate.sh` / jflow skill 改为读 JSON 驱动
- 支持 `--flow <path>` 参数指定自定义流程

**已完成（manifest v2，2026-07-09）**:
- 新增仓库默认 `workflow.json`，记录 phase name、skill、mode、model_key、output/latest、verdict、loop、resume_from，以及命名模板和别名/合法值约束。
- 新增 `bin/create-workflow-run`，每次运行从仓库根 `workflow.json` 生成 `<workspace>/workflow.json`，写入 `kind: run`、`source_manifest`、`task_name`、provider/model 和本次 `execution.order`。
- `bin/validate-workflow-manifest` 在启动时做 JSON 结构硬校验，`orchestrate.sh` 只负责调用校验结果，不再内嵌 schema 逻辑。
- `orchestrate.sh` 支持 `--flow <file>` 作为模板输入，默认使用仓库内 `workflow.json`，生成 workspace run workflow 后将其路径和 schema version 写入 `workflow-state.json` metadata。
- `bin/workflow-manifest` 统一提供 phase lookup、artifact path、template rendering、execution order、verdict/transition 解析。
- `orchestrate.sh` 已从 manifest 读取 artifact path、prompt/run/started marker 命名模板、artifact validation 规则，以及 review/revise、review-code/fix 的 verdict transition。
- `orchestrate.sh` 已根据 workspace `workflow.json` 的 `execution.order` 设置 shell phase 开关；review/revise 与 review-code/fix 的循环体仍保留显式 shell 控制流。
- 新增 `bin/validate-workspace-artifacts` 校验 workspace 产物命名、latest 指针、review/fix 轮次连续、禁止 plan 变体，以及 state phase name 是否符合 manifest 模板。
- README / jflow skill 说明：当前 manifest 用于统一描述和留档，执行循环仍由显式脚本/skill 流程驱动。

**已完成（manifest v3 / Phase C，2026-07-22）**:
- `orchestrate.sh` 已改为通用 phase 引擎，按 workspace run `workflow.json` 的 `execution.order` 执行。
- 根 manifest 使用 `execution.default_order`，shell 入口和 `/jflow` 共用同一默认顺序，包含 `review-requirement` 和 `verify-observability`。
- review/revise 与 review-code/fix 循环、breakpoint、artifact updates、VERDICT transition 由 manifest 元数据驱动。
- `jflow/SKILL.md` 已瘦身为编排器规则文档，详细阶段契约由 `workflow.json`、`prompts/` 和 `bin/` 脚本承载。

**历史备注**:
- 当前大修已收口；后续只在出现新需求时追加有明确验收标准的 follow-up。

### 21. workflow.json 状态持久化（高优，已完成）

**Problem（历史）**: 早期版本用 `.done` 文件 + Claude 内存记录进度，不可靠。断点续跑时需要 glob 扫描 `.done` 文件推断状态，容易出错。

**Fix**: 在 workspace 中维护 `workflow-state.json`，记录每阶段状态（pending/running/done/failed）、开始/结束时间、产出文件路径、session ID。编排器启动时读取状态文件恢复进度，替代 `.done` 文件和内存。

**已完成（state v2 / Phase C，2026-07-22）**:
- `bin/workflow-state` 已记录 workflow/task/provider/model/project/workspace、phase status、session_name、session_id、output_file、prompt_file、run_script、started_at、ended_at、exit_code，并作为 interactive phase 的唯一完成信号。
- 新增 workflow-level `metadata`，当前用于记录 workspace run `flow_file`、`source_manifest`、`flow_schema_version`、`ghostty_window_id`、`current_phase`、`last_finished_phase`、`current_loop`、`current_round`、`artifact_validation_status`、`last_artifact_validation`。
- review/revise 与 review-code/fix 循环会在 phase state 中记录 `round`、`loop`、`transition`、`resume_from`。
- 新增 `bin/validate-workflow-state` 做结构和合法值硬校验，`orchestrate.sh` 只负责调用。
- 续接策略已留档：revise 从 design 读取 session_id，fix 从 implement 读取 session_id；Claude 可回退 session name，Codex 必须有 session_id。
- Interactive phase 仍需要等待外部 tab 内 agent 完成，但等待对象是 `workflow-state.json` 中的 phase status，不是 `.done` 文件。started marker 只用于验证 Ghostty tab 是否成功启动，不表示阶段完成。

### 22. 输入摘要机制（中优）

**Problem**: 大 PRD 直接塞给 agent 导致 context 溢出（关联 #16）。

**Fix**: 编排器在 Phase 0 预处理时，如果 requirement.md 超过 30K 字符：
1. 拆成 N 个 batch（按章节或固定大小）
2. 并行启动 N 个摘要 agent，各自输出结构化摘要片段
3. 合并为 `requirement-summary.md`
4. 后续 agent 默认读摘要，需要细节时按章节索引精确引用原文

参考 oh-my-harness 的 batch summarize 模式。可同时解决 #16（大 PRD 溢出）。

### 23. 确认级别（低优）

**Problem**: 每个阶段完成后都需要用户确认才能推进，对于简单任务频繁打断。

**Fix**: 在 flow JSON（#20）里每个 phase 标注确认级别：
- `"confirm": "required"` — 必须用户确认（design、review 等决策点）
- `"confirm": "auto"` — 自动推进（explore、implement 等执行点）
- `"confirm": "on-failure"` — 只在失败时暂停

用户可通过 `--auto-confirm` 全局覆盖为 auto。

### 24. 大需求 context 漂移（高优）

**Problem**: 需求大时 agent 后半段质量明显下降——前面的需求细节被挤出 context window，导致实现偏移或遗漏。

**Fix**: 执行前将大需求分拆为独立子任务，可并行的交给并行 agent 各自在独立 worktree 中执行。每个 agent 只需要关注自己的子任务 context，避免单 agent 承载过大 context。

**思路**：
- design 阶段输出 task breakdown（子任务列表 + 依赖关系）
- implement 阶段根据依赖关系决定哪些子任务可并行
- 并行子任务各开独立 worktree + 独立 session
- 串行子任务在同一 session 中按序执行
- 最后 merge 各 worktree 的变更

**状态**: jesse 在调研外部方案

### 25. CR 深度不足（高优）

**Problem**: Code Review agent 经常漏问题。原因是 CR agent 直接读源码逐文件审查，缺乏全局视角——不清楚 plan 的设计意图、不了解实现的整体架构，只能做表面检查。

**Fix**: 阶段边界生成结构化摘要，CR agent 先建立全局理解再深入：
1. design 阶段结束时输出 `plan-digest.md`（方案要点、关键设计决策、需要验证的点）
2. implement 阶段结束时输出 `impl-digest.md`（改了哪些文件、每个文件的变更意图、新增的关键逻辑）
3. CR agent 先读两份 digest 建立全局理解
4. 然后按维度逐个读源码深入检查（而非逐文件浏览）

**检查维度**（从 digest 驱动）：
- 设计意图是否正确实现
- 边界条件和异常路径
- 并发安全
- 性能影响
- 可观测性覆盖

### 26. 需求变更重入质量下降（高优）

**Problem**: 需求变更后从 design 重入（复用旧 session），agent 只关注变更点 A，忽略旧方案中已有的设计决策 B/C/D。表现为"思路阻塞、只看一个点"。

**可能原因**：
1. /design skill 的"从零设计"框架 — skill 指令引导 agent 走完整新设计路径，即使旧推理在上下文中也不主动回顾
2. 上下文长度 / 注意力衰减（lost in the middle）— 旧 session 经历多轮后 context 很长，旧设计决策埋在中间关注度下降
3. 两者叠加
4. "参考"措辞太弱（新 session 场景）— prompt 说旧方案"可作参考"暗示从零开始
5. 归档清空 workspace 的暗示（新 session 场景）— plan.md 被移到 archive/，物理层面暗示重头来
6. 新 session 无决策记忆（新 session 场景）— 推理上下文全丢，读旧 plan.md 只看到结论看不到 why

**解法方向（待验证）**：
- A. 重入时不调 /design skill，改用类似 /revise 的增量修改模式
- B. 重入前让 agent 先输出旧方案关键决策点摘要，锚定注意力
- C. 新 session + 旧 plan.md 作为基线 + 增量修改 prompt
- D. 限制旧 session 上下文长度（compaction 或截断）

### 27. 轻量修复 agent — patch（中优）

**Problem**: 测试问题和人工 CR 建议需要快速修复，不需要走完整 TDD 流程。

**Fix**: 新增 patch agent，直接改代码+同步修单测+跑测试验证。是否续接 implement session 待定。

### 28. CLAUDE.md 瘦身 + 按需加载（中优）

**Problem**: Archery 映射和 Log Query 规则占 CLAUDE.md 60%，但只有 review-plan/verify-observability 用到。每个 agent 都白加载。

**Fix**: 移到对应 skill 的 references/ 目录，agent 按需 Read。CLAUDE.md 从 ~200 行降到 ~35 行，每个 agent 省 ~2K tokens。

### 29. 用 DDD 思路重构 Agent / Workflow 领域模型（中优）

**Problem**: 现有设计主要围绕脚本流程和文件路径展开，agent、provider、session、phase、workflow state、产出物之间的边界还不够清晰。随着 Codex / Claude Code 多 provider、JSON 状态、动态 flow、重入、并行 worktree 等能力增加，继续按脚本变量堆叠会让语义分散，后续维护和扩展成本上升。

**Fix**: 在进入更大规模重构前，用 DDD 思路重新审视核心领域模型，明确 bounded context、实体、值对象、聚合根和领域服务。

**初步建模方向**：
- Workflow Run：一次编排执行的聚合根，负责阶段推进、状态恢复、产物索引
- Phase / Phase Attempt：阶段定义与某一轮执行实例分离，支持 review-rN、fix-rN、重试和重入
- Agent Role：explore、design、review-plan、implement、review-code、fix 等角色，定义输入/输出契约
- Provider：Claude Code / Codex 的能力适配层，负责启动、resume、model、环境变量和 session id 发现
- Session：provider session 的领域对象，记录 session id、session name、resume 语义和归属 phase
- Artifact：requirement、plan、review、impl-notes、code-review、fix-notes 等产出物，统一记录路径、版本和 latest alias
- Execution Target：项目目录、worktree、关联项目、terminal/Ghostty tab 等执行上下文

**需要回答的问题**：
- `workflow-state.json` 应该是 Workflow Run 的持久化视图，还是事件日志 / 状态快照组合？
- `workflow.json` 是流程定义的 DSL，还是 Agent Role 的配置集合？
- provider 自动推断、显式选择和主 agent 传参应归属于哪个领域服务？
- `orchestrate.sh` 和 `/jflow` skill 是否共享同一个领域模型和脚本 helper？
- 重入、归档、并行 worktree 应该由 Workflow Run 管，还是由独立的 Workspace/Execution 服务管？

**产出目标**：
- 新增 `docs/domain-model.md` 或 ADR，记录领域对象、关系、状态机和关键不变量
- 基于领域模型再拆分脚本 helper，避免 `orchestrate.sh` 和 `/jflow` skill 重复实现
- 为后续 #20 声明式 flow JSON、#21 workflow-state.json、#24 并行 worktree、#26 重入质量修复提供统一设计基础

### 30. design agent 引入 DDD 设计方法（中优）

**Problem**: 当前 `/design` skill 更偏工程方案模板，重点覆盖复用分析、数据模型、接口、流程、性能和可观测性，但没有显式要求 agent 先做领域建模。对于业务复杂需求，design agent 容易直接按 CRUD、接口或表结构拆方案，忽略领域边界、聚合、不变量和领域服务职责。

**Fix**: 后续调整 `/design` skill，让技术方案设计默认使用 DDD 思路，但不要求所有需求都过度建模。

**设计要求方向**：
- Step 1 理解需求时提取领域语言、业务动作、状态、规则和不变量
- 在方案概述中增加领域建模摘要：bounded context、实体、值对象、聚合根、领域服务/应用服务、关键不变量
- 数据模型章节说明表结构与领域模型的映射关系，以及聚合边界内的一致性策略
- 核心流程章节按应用服务 / 领域服务 / 基础设施层说明职责边界
- 对简单需求允许明确说明“不单独引入聚合/领域服务”的理由，避免为了 DDD 而 DDD

**涉及改动**：
- `design/SKILL.md` — 增加 DDD 建模步骤和 plan.md 输出要求
- `review-plan/SKILL.md` — 增加对领域边界、业务不变量和职责分层的评审点
- 可能需要补充 `design/references/ddd.md`，避免把完整 DDD 说明塞进主 skill

### 31. review-plan 验证方案隐含假设（高优）

**Problem**: `review-plan` 当前主要靠主动探索现有系统来发现问题，但缺少一个被动核查动作：把方案中关于现有代码行为的陈述和隐含前提提取出来，逐条读代码验证。实际测试中，方案声称需要新增兼容解密方法，但现有方法的异常兜底已经满足兼容行为；评审只验证了新方法设计本身，没有验证“现有方法不满足”的前提，导致不必要设计进入修正阶段。

**Fix**: 增强 `review-plan/SKILL.md`：
- Step 2 增加“提取并验证方案隐含假设”子步骤
- 对方案中“现有方法/类做什么”的描述，必须读源码验证
- 对新增方法/类，必须找最相近现有实现，用新场景典型输入推演执行路径
- 特别追查异常传播链，确认异常是否已被上层兜住并返回可用结果
- Checklist 1 复用性从“是否有类似实现”改为“读代码验证现有实现是否已满足新场景”
- 在注意事项中明确：评审者的认知必须来自自己读代码，方案对现有系统的描述只是待验证假设

**涉及改动**：
- `review-plan/SKILL.md`

**已完成（skill 规则，2026-07-08）**:
- `review-plan/SKILL.md` 新增 Step 2.5：提取并验证方案隐含假设。
- 要求对现有方法、类似实现、异常传播链、复用点、配置/枚举/状态等逐条读代码验证。
- 评审报告新增“隐含假设验证”小节。

### 32. 纯分析阶段迁移到原生 Agent / 非 Ghostty 执行（中优，部分完成）

**Problem（历史）**: 早期版本所有阶段都通过 Ghostty 新 tab 启动独立 session，并用完成 marker 轮询。对 review-requirement、explore、review-plan、review-code、verify-observability 这类纯分析阶段来说，开 tab、生成 run script、导出环境变量、AppleScript、轮询完成状态都偏重。

**Fix**: 将纯分析阶段改为更轻量的执行模式，保留 design / implement / revise / fix 的 Ghostty 隔离和可交互续接。

**候选范围**：
- review-requirement：纯分析，无续接需求
- explore：纯调研，无深度交互
- review-plan：纯评审，产出 review.md + VERDICT
- review-code：纯评审，产出 code-review-rN.md + VERDICT
- verify-observability：纯验证，产出验证报告

**实现方向**：
- `/jflow` skill 中优先用原生 Agent tool 调用这些阶段，Agent 返回即完成，不写 marker 文件
- `orchestrate.sh` 可选增加 `run_phase_native` / print-mode 执行路径，用于非交互分析阶段
- design / implement / revise / fix 继续使用 Ghostty tab，因为它们需要深度交互、跨天续接或精确 resume

**风险和待确认**：
- shell 版 `orchestrate.sh` 使用 Claude/Codex CLI 的非交互模式时，是否能稳定调用本地 skills，需要单独验证
- 原生 Agent 模式和独立 session 隔离目标是否冲突，需要明确“隔离”的最低要求是上下文隔离还是终端 tab 隔离

**涉及改动**：
- `jflow/SKILL.md`
- `orchestrate.sh`

**已完成（skill 流程，2026-06-22）**:
- `/jflow` skill 已将 review-requirement、review-plan、review-code、verify-observability 定义为 Subagent phase。
- Subagent phase 不生成 run script、不打开 Ghostty tab、不写 marker 文件，由主 agent 通过 Agent tool 派发、检查报告和 VERDICT。
- explore 暂不子 agent 化，避免与 Claude 原生 Explore subagent 混淆。
- design / revise / implement / fix 保持 Ghostty interactive phase。
- Codex 无 Agent tool 时不强行模拟复杂子 agent，按同一约束直接执行分析 phase 或使用已验证的非交互 CLI runner。

**历史备注**:
- shell 入口 `orchestrate.sh` 与 `/jflow` 流程术语已在 Phase C/D 中对齐。
- review-requirement / verify-observability 已接入 shell 编排器并复用同一分析 runner 约束。

### 33. Ghostty 窗口选择持久化与手动指定（低优）

**Problem**: 当前修复已在编排器启动时检测一次 Ghostty frontmost window id，并在本次进程内传给 `ghostty-open-tab`，避免非 TTY 调用时 title-marker 检测失败导致每阶段开新窗口。但窗口 id 还没有持久化到 `workflow-state.json`，`--resume` 新进程会重新检测 frontmost window；如果用户此时切到另一个 Ghostty 窗口，后续阶段可能开到错误窗口。

**Fix**:
- 在 `workflow-state.json` 增加 workflow-level metadata，记录 `ghostty_window_id`
- `orchestrate.sh --resume` 优先读取 state 中的窗口 id，只有缺失时才重新检测 frontmost window
- 增加显式参数 `--ghostty-window-id <id>`，允许用户手动指定目标窗口
- `jflow/SKILL.md` 同步说明窗口 id 的保存、恢复和手动覆盖规则

**暂缓原因**: 当前 `workflow-state` helper 还没有通用 metadata API，强行写入会扩大状态模型改动面。先用进程变量解决“每阶段误开新窗口”的主要问题。

### 34. Explore 阶段 provider-aware 轻量化（中优）

**Problem**: `/explore` skill 是本项目自定义的需求探索阶段，但 Claude Code 也有原生 Explore subagent type，两个概念容易混淆。当前 `/explore` skill 文档直接写“派发多个 Explore subagent”，容易让实现误以为所有 provider 都有同名原生能力，也容易过度设计 Codex 适配。

**Clarification**:
- Claude Code 原生 Explore subagent：适合代码定位、搜索、摘录，作为 `/explore` 内部可选 worker。
- 本项目 `/explore` skill：负责需求探索阶段的 coordinator，产出 `explore/exploration.md`。
- Codex 当前不需要实现复杂并行子 agent；保持直跑 `/explore`，用 `rg`/CodeGraph/普通读取完成探索即可。

**Fix**:
- 调整 `explore/SKILL.md`：不要强制指定 `subagent_type: Explore`，只说明“如果 provider 支持轻量探索 subagent，可按需使用；否则直接用代码搜索工具探索”。
- Claude 路径允许 agent 自行决定是否调用原生 Explore subagent，不在 workflow/orchestrate 层硬编码。
- Codex 路径不做多 worker 编排，避免增加复杂度。
- `/explore` 的输出仍必须是 `explore/exploration.md`，包含路径、符号、证据、未覆盖范围。

**涉及改动**:
- `explore/SKILL.md`
- `jflow/SKILL.md`（如有阶段说明需要澄清）

**已完成（skill 规则，2026-07-08）**:
- `explore/SKILL.md` 改为 provider-aware 探索。
- Claude 原生 Explore subagent 仅作为可选能力，不再强制指定。
- Codex / 无子 agent 环境明确走 `rg` / CodeGraph / Glob / Read 直接探索。

### 35. 自定义 `/explore` skill 改名以避免和 Claude 原生 Explore 混淆（中优）

**Problem**: 本项目的 `/explore` skill 与 Claude Code 原生 Explore subagent 同名，但职责不同。前者是需求探索阶段，后者是代码搜索/定位 worker。同名会导致讨论、prompt、日志和后续 provider 适配都混乱。

**候选命名**:
- `/investigate`：强调调研现有系统，较通用。
- `/analyze-system`：强调系统分析，但略长。
- `/research-codebase`：强调代码库调研，但偏英文语境。
- `/scope-requirement`：强调需求落地范围，但不如 investigate 直观。

**推荐**: 将本项目 `/explore` 改名为 `/investigate`。保留兼容入口 `/explore` 一段时间，文档中标注 deprecated。

**Fix**:
- 新增或重命名 `investigate/SKILL.md`。
- `jflow/SKILL.md` 和 `orchestrate.sh` 将 Phase 1 从 `/explore` 改为 `/investigate`。
- 保留 `explore/SKILL.md` 作为兼容 wrapper，提示“请调用 /investigate skill”。
- README、CHANGELOG、backlog 中更新命名说明。

**涉及改动**:
- `explore/SKILL.md`
- `investigate/SKILL.md`
- `jflow/SKILL.md`
- `orchestrate.sh`
- `README.md`
- `CHANGELOG.md`

### 36. `/jflow` skill 与 Claude 原生 Dynamic Workflow 概念冲突（中优）

**Problem**: Claude Code 现在会在普通实现任务中弹出 `Run a dynamic workflow?` 确认页，例如自动规划 `Scan Patterns / Create Models / Create Controllers / Create Skill / Verify` 等阶段，并提示可用 `/workflows` 管理、在 `/config` 关闭。这不是本项目 `/jflow` skill 内部流程触发的，但名字和语义容易混淆：用户看到 "workflow" 可能无法判断是 Claude 原生 dynamic workflow，还是本项目的 `/jflow` 编排器。

另一个相关现象是 Claude 原生 dynamic workflow 或非交互子流程可能报 `Please run /login · API Error: 401 Authentication Error, No api key passed in.`。这通常不是 j-workflow phase 产物合同失败，而是 Claude Code 原生 workflow/subagent 执行路径没有拿到当前会话的认证态，或走到了需要 `ANTHROPIC_API_KEY` 的 API-key 认证路径。

**Clarification**:
- Claude 原生 Dynamic Workflow：Claude Code runtime 的能力，用于把大任务拆成多个并行 subagents，可能消耗大量 token，并由 Claude Code 自己弹出确认。
- 本项目 `/jflow` skill：需求到设计、评审、实现、代码评审的工程编排器，产物落在 `.workflow/<name>/`，有固定 phase/output/VERDICT 合同。
- 这不是当前 flow 内部 bug，而是命名和概念重叠导致的认知冲突。
- 认证错误需要单独处理：不能假设原生 dynamic workflow 一定继承当前交互式 Claude Code 的 `/login` 状态。

**Potential positive use**:
- 在本项目 `implement` 阶段中，如果 provider 是 Claude Code，且任务天然可以拆分为低耦合子任务（如批量创建模型、批量补测试、多个独立 endpoint），可以允许 implement agent 在明确提示用户并获得确认后调用 Claude 原生 dynamic workflow。
- 原生 dynamic workflow 只能作为 implement 阶段内部的执行加速手段，不能替代 `/jflow` 的阶段产物合同：仍必须写 `implement/impl-notes.md`，仍必须接受 `review-code` 阶段检查。
- 不应在 review-plan / review-code 这类分析 phase 中触发原生 dynamic workflow，避免 token 爆炸和上下文不可控。
- 如果原生 dynamic workflow 报 `/login` 或 `No api key passed in`，implement agent 应停止使用该能力，回退到普通实现流程，并在 `impl-notes.md` 记录认证阻塞；不要反复重试消耗 token。

**Fix**:
- 在 `jflow/SKILL.md` 中增加术语说明：`/jflow` skill 与 Claude Code `/workflows` / dynamic workflow 是不同机制。
- 将本项目文档中的泛化 "workflow" 表述收窄为 "j-workflow orchestration" 或 "phase orchestration"，减少误导。
- 在 `implement/SKILL.md` 中增加可选规则：只有在用户确认、任务可并行、且能保持产物合同时，Claude implement agent 才可使用原生 dynamic workflow。
- 在 `implement/SKILL.md` 中增加认证前置检查：使用原生 dynamic workflow 前确认 Claude Code auth 可用；遇到 401 `/login` / `No api key passed in` 时回退到普通实现，不把它当作代码实现失败。
- 在 README 中补充一段 provider-specific note，说明 Claude Code dynamic workflow 弹窗不代表 j-workflow 正在运行。

**涉及改动**:
- `jflow/SKILL.md`
- `implement/SKILL.md`
- `README.md`
- `docs/multi-agent-workflow-optimizations/README.md`

**已完成（skill/docs，2026-07-08）**:
- `jflow/SKILL.md` 增加术语边界：j-workflow `/jflow` 与 Claude Code `/workflows` / dynamic workflow 不是同一机制。
- `implement/SKILL.md` 增加 Claude 原生 dynamic workflow 使用边界、用户确认要求和 401 回退规则。
- README 增加 Claude Code provider note。

### 37. Design / Implement 是否合并为同一 Agent 或同一长会话（中优）

**Problem**: 当前 design 和 implement 是两个独立阶段、两个独立 agent session。好处是职责清晰、评审隔离、上下文边界明确；问题是 implement agent 只能通过 design 交付文件理解设计意图，读不到 design 阶段的推理过程和用户讨论细节。复杂需求中，如果 `plan.md` 没有精确表达所有必须改动，implement 容易漏上下文或误解方案。

**Tradeoff**:
- 合并为同一 agent / 同一长会话：设计意图连续，用户讨论不丢，实现时更懂 why；但上下文更容易膨胀，design 阶段的探索噪音会进入 implement，review-plan 后的修正也可能让长会话注意力漂移。
- 保持独立 agent + 强设计交付：上下文可控，review-plan 能作为明确阶段闸门；但要求 `plan.md` 作为唯一权威来源足够完整，所有必须信息都要文件化。`implementation-brief.md` 只能作为 plan-derived checklist / trace index，不能补充 plan 外设计。

**Current direction**:
- 默认仍保持 design / implement 分离。
- 强化 design 交付完整性：`plan.md` 是唯一权威设计与实现依据；`implementation-brief.md` 是从 plan 派生的核对索引，必须精准映射 Required Changes、Contract Changes、Cross-repo Sync Points、Tests Required，且每项能回链到 plan。
- 对小型、低风险、无需严格评审的任务，未来可提供可选模式：`design+implement` 由同一个 interactive agent 连续完成，但仍必须先写设计摘要和 implementation brief，再开始改代码。

**Fix options**:
- Option A（推荐短期）：继续分离阶段，完善 `plan.md` 交付完整性要求，并用 `implementation-brief.md` 作为覆盖性校验索引，确保新 session 可从 plan 独立复原实现意图。
- Option B：新增 `--merge-design-implement` / workflow 参数，仅对简单任务启用；design agent 在用户确认方案后直接进入 implement。
- Option C：保持两个阶段但复用同一 provider session：implement 续接 design session，并在开始实现前强制重新读取完整 `plan.md` 和 plan-derived `implementation-brief.md`；文件优先于历史上下文，冲突时回到 design/revise 修 design 产物。

**涉及改动**:
- `jflow/SKILL.md`
- `design/SKILL.md`
- `implement/SKILL.md`
- `orchestrate.sh`
- `README.md`

## Not Adopted

| Proposal | Reason |
|----------|--------|
| Python 控制层（oh-my-harness 模式） | 独立 session 隔离 context 比单 session ping-pong 更适合长流程 |
| oh-my-harness 回滚机制 | 我们的归档重入（archive/round-N）更完整，支持需求变更重跑 |

## Files Involved

Repository source paths:
- `orchestrate.sh` — Shell 编排器
- `bin/` — shared helper scripts
- `review-requirement/SKILL.md` — 需求审视 skill
- `design/SKILL.md` — 方案设计 skill
- `review-plan/SKILL.md` — 方案评审 skill
- `implement/SKILL.md` — TDD 实现 skill
- `review-code/SKILL.md` — 代码评审 skill
- `verify-observability/SKILL.md` — 可观测性验证 skill
- `jflow/SKILL.md` — 编排器 skill

Provider install locations are environment-specific. Do not assume `~/.claude` exists in Codex-only environments; Claude Code defaults to `~/.claude` and may be overridden with `CLAUDE_HOME`, while Codex defaults to `~/.codex` and may be overridden with `CODEX_HOME`.
