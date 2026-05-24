# Multi-Agent Workflow — Remaining Optimizations (Improvement Backlog)

Related:
- Main README: [`../../README.md`](../../README.md)
- Changelog: [`../../CHANGELOG.md`](../../CHANGELOG.md)

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
  --model claude-sonnet-4-6 \
  --model-design claude-opus-4-6 \
  --model-review claude-opus-4-6
```
需改动：orchestrate.sh（参数解析 + run_phase 读取阶段模型）、workflow skill（支持生成新参数）、README。

### 5. ~~错误恢复和断点续跑~~ → Done (2026-04-13)

已实现 `--resume` 参数。

### 8.5 Claude Session 断点续接 — 精确 resume（中优）

**Problem**: revise 用 `--resume <session-name>` 续接 design session，但多次测试后会产生多个同名 session，导致弹出交互式选择器而非自动续接。

**Fix**: 改用 `--session-id <uuid>` 精确续接。design 阶段结束后从 `~/.claude/sessions/` 中按 name 查找最新的 session ID 写入 `design/.session-id`，revise 时读取并用 `--session-id` 续接。

### 6. 产出质量自动校验（低优）

**Problem**: 每阶段只检查输出文件是否存在，不检查内容是否完整。plan.md 可能缺少"可观测性"章节但仍被认为"完成"。

**Fix**: 对 plan.md 和 review.md 做章节标题校验，缺少必需章节时警告或重跑。

### 9. 编排器迁入 Claude Code（高优）

**Problem**: 当前编排器是独立 shell 脚本 (`orchestrate.sh`)，入口在终端而非 Claude Code。用户需要离开 Claude Code 去终端执行命令，编排器的断点交互（`read`）也很原始，无法灵活调整参数、跳过阶段或与编排器对话。

**Fix**: 将编排逻辑从 `orchestrate.sh` 迁入 Claude Code skill（`/workflow` 或新 skill），用 Bash `run_in_background` 驱动：

1. Claude Code 做准备工作（理解需求、拉飞书文档、生成 requirement.md、确认参数）
2. 每个阶段：Bash `run_in_background` 开 Ghostty 新 tab + 轮询 `.done`
3. Agent 在新 tab 里执行，用户在 tab 内和 agent 交互，确认后 agent 写 `.done`
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
- 新建或重构 `/workflow` skill 为编排器
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
- `workflow/SKILL.md` — 编排器在阶段间确认前发通知
- 新增 `~/.claude/bin/notify-lark.sh`（或内联到编排器）
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
- `workflow/SKILL.md` — Phase 0 新增摘要步骤，各阶段 prompt 改为引用摘要
- `orchestrate.sh` — 同步新增摘要步骤
- 新增 `~/.claude/skills/summarize-requirement/SKILL.md`（或内联到编排器）
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
- `orchestrate.sh` / workflow skill 改为读 JSON 驱动
- 支持 `--flow <path>` 参数指定自定义流程

### 21. workflow.json 状态持久化（高优）

**Problem**: 当前用 `.done` 文件 + Claude 内存记录进度，不可靠。断点续跑时需要 glob 扫描 `.done` 文件推断状态，容易出错。

**Fix**: 在 workspace 中维护 `workflow-state.json`，记录每阶段状态（pending/running/done/failed）、开始/结束时间、产出文件路径、session ID。编排器启动时读取状态文件恢复进度，替代 `.done` 文件和内存。

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

## Not Adopted

| Proposal | Reason |
|----------|--------|
| Python 控制层（oh-my-harness 模式） | 独立 session 隔离 context 比单 session ping-pong 更适合长流程 |
| oh-my-harness 回滚机制 | 我们的归档重入（archive/round-N）更完整，支持需求变更重跑 |

## Files Involved

- `~/.claude/bin/orchestrate.sh` — Shell 编排器
- `~/.claude/skills/review-requirement/SKILL.md` — 需求审视 skill
- `~/.claude/skills/design/SKILL.md` — 方案设计 skill
- `~/.claude/skills/review-plan/SKILL.md` — 方案评审 skill
- `~/.claude/skills/implement/SKILL.md` — TDD 实现 skill
- `~/.claude/skills/review-code/SKILL.md` — 代码评审 skill
- `~/.claude/skills/verify-observability/SKILL.md` — 可观测性验证 skill
- `~/.claude/skills/workflow/SKILL.md` — 编排器 skill
