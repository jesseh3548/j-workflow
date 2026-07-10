---
name: workflow
description: "多 Agent 编排器。根据用户需求，由主 agent 编排子 agent 分析阶段和 Ghostty 交互阶段，完成需求审视→设计→评审→修正→实现→代码评审。"
argument-hint: "[需求描述或飞书链接]"
allowed-tools: ["Read", "Write", "Bash", "AskUserQuestion", "Skill", "Glob", "Grep", "Agent"]
---

# Workflow — 多 Agent 编排器

你是编排器。你在 Claude Code 或 Codex 主对话中运行，负责准备 workspace、派发阶段任务、检查阶段产物、决定是否推进下一阶段。

仓库根目录的 `workflow.json` 是默认 phase manifest / 模板，记录阶段元数据、产物合同、模型 key、命名模板、verdict transition 和 resume policy。每次运行必须在 workspace 内生成一份同名 `workflow.json` 作为本次 run workflow；它根据用户需求和确认结果写入 `execution.order`，后续编排按 workspace `workflow.json` 推进，`workflow-state.json` 只记录实际运行状态并引用该文件。

脚本边界：通用能力必须放在脚本库 `bin/` 中，`orchestrate.sh` 只负责编排和调用。manifest 读取用 `bin/workflow-manifest`，manifest 校验用 `bin/validate-workflow-manifest`，state 写入用 `bin/workflow-state`，state 校验用 `bin/validate-workflow-state`，artifact 校验用 `bin/validate-artifact`，provider 非交互执行用 `bin/run-provider-noninteractive`，phase run script 渲染用 `bin/render-phase-run-script`。不要把这些能力重新内联进 `orchestrate.sh`。

阶段执行分两类：

| 模式 | 阶段 | 执行方式 | 适用原因 |
|------|------|----------|----------|
| Subagent phase | review-requirement / review-plan / review-code / verify-observability | 主 agent 使用 Agent tool 派发独立子 agent；子 agent 写报告后返回 | 纯分析/评审/验证，不需要长会话和用户在 tab 内交互 |
| Interactive phase | explore / design / revise / implement / fix | Ghostty 新 tab 中启动独立 agent session | 需要用户交互、长时间上下文、或精确 resume |

Codex 兼容规则：如果当前 Codex 运行环境没有可用的 Agent tool，不要强行模拟复杂子 agent。主 agent 可以按同一 prompt 在当前 session 直接执行该分析阶段，或使用已验证的非交互 CLI runner；但必须遵守同样的产物、VERDICT、只读/只写报告约束。

术语边界：本项目 `/workflow` skill 是 j-workflow phase orchestration。Claude Code 的 `/workflows` / `Run a dynamic workflow?` 是 Claude Code runtime 的原生 dynamic workflow 能力，两者不是同一个机制。看到 Claude 原生 dynamic workflow 弹窗，不代表 j-workflow 已进入 `.workflow/<name>/` 编排流程。

## 核心流程

```
主对话（你 = 编排器）
  │
  ├── 1. 理解需求 → 确认参数
  ├── 2. 准备 workspace
  │
  ├── 2.5 派发 review-requirement subagent
  │     ├── 审视需求合理性（逻辑矛盾、边界模糊、可扩展性、外部知识验证）
  │     ├── 检查 VERDICT → NEEDS_CLARIFICATION 时暂停等用户澄清
  │     └── PASS 后继续
  │
  ├── 3. 启动 design agent（Ghostty 新 tab）
  │     ├── Bash run_in_background: 轮询 workflow-state.json
  │     ├── 用户在 tab 内和 agent 交互
  │     ├── agent 完成 → 用户确认 → agent 写 workflow-state
  │     └── 后台任务完成 → 通知回到主对话
  ├── 4. 问用户：要继续进入评审吗？
  │
  ├── 5. 派发 review-plan subagent
  ├── 6. 检查 VERDICT → 如需修正 → 启动 revise agent
  │
  ├── 7. 启动 implement agent
  ├── 8. 派发 review-code subagent
  ├── 9. 检查 VERDICT → 如需修复 → 启动 fix agent（循环）
  ├── 10. 派发 verify-observability subagent
  └── 11. 汇总产出
```

## 权威产物同步规则

最终交付时，`design/plan.md` 必须是完整、准确、最新的事实来源。任何阶段、任何对话中达成的新结论都不能只留在聊天、review 报告、fix-notes 或实现代码里。

必须同步回 `design/plan.md` 的内容包括：
- 用户在主 agent 对话中补充的人工 CR 结论、取舍、边界、暂缓项、忽略项。
- review-code / fix 阶段确认的实现细节、兼容策略、异常处理、测试边界、可观测性口径。
- 因修复而改变或澄清的接口契约、数据模型、状态流转、配置项、跨仓同步点。
- 任何后续 agent 需要知道才能独立复现实现和评审判断的细节。

同步方式：
- 直接修改 `design/plan.md` 的对应章节，让它保持一份完整自洽的方案，不要只在末尾追加流水账。
- 如变更影响实现核对项，同步更新 `design/implementation-brief.md`，确保 brief 仍完全由 plan 派生，且没有 plan 外内容。
- 如果当前阶段没有直接编辑 design 产物的权限或上下文，应停止推进并回到 revise/design 完成同步；不能让最新事实只存在于 fix-notes。
- 只有纯代码机械修复且不改变任何方案含义、边界、验证口径时，才允许只记录在 fix-notes。

## 版本化产出命名规范

所有产出文件遵循统一的版本命名规则。**Agent prompt 中会指定具体文件名，必须严格使用指定的名称。**

### 两种版本概念

| 概念 | 格式 | 含义 | 示例 |
|------|------|------|------|
| 迭代轮次 | `-rN` 后缀 | 同一阶段内的 review-fix 循环迭代 | `review-r1.md` → `review-r2.md` |
| 全流程重入 | `archive/round-N/` 目录 | 需求变更导致整个流程重新开始 | `archive/round-1/` |

### 迭代轮次命名（`-rN` 后缀）

迭代从 r1 开始。每次归档（全流程重入）后，迭代计数器**重置为 r1**。

**Design-Review 循环：**

| 轮次 | 评审报告 | 修正说明 | 修正后方案 |
|------|----------|----------|-----------|
| 初始 | — | — | `design/plan.md`（原始方案） |
| r1 | `review/review-r1.md` | `review/revise-notes-r1.md` | `design/plan-r1.md` |
| r2 | `review/review-r2.md` | `review/revise-notes-r2.md` | `design/plan-r2.md` |

**Code Review-Fix 循环：**

| 轮次 | 评审报告 | 修复说明 |
|------|----------|----------|
| r1 | `review-code/code-review-r1.md` | `review-code/fix-notes-r1.md` |
| r2 | `review-code/code-review-r2.md` | `review-code/fix-notes-r2.md` |

### Latest 指针

每轮结束后，编排器执行 cp 保持 latest 指针更新。`design/plan.md` 是最终唯一权威方案文件，命名必须保持最简单；任何阶段确认的新事实都同步回这个文件。版本化的 `plan-rN.md` 只用于 revise 中间产物和审计，不是下游输入。

| 指针文件 | 更新时机 | 命令 |
|----------|----------|------|
| `review/review.md` | review 完成后 | `cp review-rN.md review.md` |
| `design/plan.md` | revise 完成后 | `cp plan-rN.md plan.md` |
| `design/plan.md` | fix/manual CR 确认新事实后 | 直接就地更新 `plan.md` 对应章节，不创建新的 plan 命名 |
| `review-code/code-review.md` | review-code 完成后 | `cp code-review-rN.md code-review.md` |

### 不带版本号的产出

以下文件只有一份，不参与迭代循环：

- `requirement.md` — 需求文档
- `requirement-review/requirement-review.md` — 需求审视报告
- `explore/exploration.md` — 探索报告
- `implement/impl-notes.md` — 实现说明
- `verify-observability/observability-report.md` — 可观测性验证报告

### 禁止的命名

- ❌ `round-1.md`、`round-3-r1.md` — 不要把 round（全流程重入）混入文件名，round 只用于 archive 目录
- ❌ `plan-part1.md` — 不要用 part 拆分文件，一个阶段一份完整文档
- ❌ `plan-fix-r1.md`、`plan-final.md`、`final-plan.md` — 最完整、最新的方案只能叫 `design/plan.md`
- ❌ 跳号（如从 r1 直接到 r5）— 归档后计数器重置，在当前 workspace 内从 r1 开始
- ❌ 无版本号的迭代产出（如 `revise-notes.md` 无后缀）— 循环中的每份产出都必须带 `-rN`

## Phase 0: 理解需求与准备

### 0.1 理解用户意图

从用户的描述中判断：
- **项目是哪个？** — 如果用户没说，问一下
- **需求名称** — 提取一个简短名称（如"卡对账"、"EU区域对接"）
- **需求来源** — 飞书链接、本地文件、口述
- **要跑哪些阶段** — 默认全流程，可跳过部分
- **Provider** — `claude` 或 `codex`。优先使用用户指定值；未指定时可交给 `orchestrate.sh` 自动推断
- **模型** — Claude 默认使用 Claude CLI 自身配置的模型；Codex 默认读取 `~/.codex/config.toml`，读不到时使用 gpt-5.5；复杂需求可按 provider 选择更强模型
- **阶段模型覆盖** — 如用户希望设计/评审使用更强模型、实现使用较快模型，支持按阶段覆盖：`model_explore`、`model_design`、`model_review` / `model_review_plan`、`model_revise`、`model_implement`、`model_review_code`、`model_fix`。未指定的阶段继承全局模型。

### 0.2 获取需求文档

| 来源 | 处理 |
|------|------|
| 飞书/Lark 链接 | 用 `/lark-doc-skills:lark-doc` 拉取，写入 workspace/requirement.md |
| 本地文件路径 | 复制到 workspace/requirement.md |
| 口述 | 整理后写入 workspace/requirement.md |

### 0.3 确认参数

用 AskUserQuestion 确认：

1. **阶段范围** — 全流程 / 只出方案+评审 / 跳过代码评审
2. **Provider** — Claude Code / Codex（默认按当前上下文推断）
3. **模型** — 按 provider 选择。Claude Code 默认使用 CLI 自身配置，也可显式指定 Sonnet / Opus；Codex 可选本机默认模型（读取 `~/.codex/config.toml`）/ 指定模型（如 `gpt-5.5`）
4. **是否需要需求审视** — 默认开启。需求来源是飞书 PRD 或口述时建议开启；需求已经过充分讨论且边界清晰时可跳过
5. **是否需要探索阶段** — 仅当需求文档中代码定位不够明确时
6. **是否需要阶段模型覆盖** — 默认不需要。复杂需求可让 design/review-plan/review-code 使用更强模型，implement/fix 使用默认模型。

可根据上下文省略已明确的选项。

### 0.4 准备 workspace

**第一步（强制）：检查旧产出并归档**

在创建或写入任何文件之前，必须先检查 workspace 是否已存在产出。不要在 skill 中重新实现归档逻辑；统一调用共享脚本：

```bash
# 检查是否已有旧产出
bin/archive-workspace --workspace "<workspace>" --check-only

# 如需归档并清空当前工作目录
bin/archive-workspace --workspace "<workspace>"
```

行为约定：
- `--check-only` 检测到旧产出时输出 `has-artifacts` 并 exit 0；没有旧产出时 exit 1。
- 默认模式会归档 `requirement-review/`、`explore/`、`design/`、`review/`、`implement/`、`review-code/`、`verify-observability/`、`requirement.md`、`idea.txt`、`workflow.json`、`workflow-state.json` 到 `archive/round-N/`，然后清空当前阶段目录和 workspace 根的 run workflow/state。
- `--resume` 或用户明确要求续跑时，不要归档。
- 需求中途变更重入时，同样调用该脚本归档旧 run，再生成新的 workspace `workflow.json` 和 `workflow-state.json`。

**第二步：创建目录结构并复制需求文档**

```
<project>/.workflow/<需求名>/
  ├── workflow.json        # 本次运行计划，从仓库根 workflow.json 生成
  ├── workflow-state.json  # 本次运行状态
  ├── requirement.md
  ├── requirement-review/    # 需求审视
  ├── explore/
  ├── design/
  ├── review/
  ├── implement/
  ├── review-code/
  ├── verify-observability/
  └── archive/          # 归档目录（按需创建）
      └── round-N/
```

用 Bash 创建目录结构，复制需求文档。

**第三步：生成本次 run workflow**

从仓库根 `workflow.json` 读取默认 phase manifest，根据用户确认的阶段范围、provider、模型和跳过项，生成 `<workspace>/workflow.json`。不要直接修改仓库根 `workflow.json`。

本次 run workflow 必须包含：
- `kind: "run"`
- `source_manifest` 指向仓库根 `workflow.json`
- `task_name`、`provider`、`model`
- `execution.order`：本次实际执行顺序，例如完整流程包含 review-requirement、design、review-plan、revise、implement、review-code、fix、verify-observability；bugfix flow 可只包含 implement、review-code、fix
- `execution.disabled`：未进入本次 run 的 phase

初始化 `workflow-state.json` 后，必须将 `metadata.flow_file` 指向 `<workspace>/workflow.json`。需求中途变更时，旧的 workspace `workflow.json` 和 `workflow-state.json` 必须一起归档，再基于新需求生成新的 workspace `workflow.json` 和 state。

**第四步：检查 CLAUDE.md**

检查项目目录是否有 CLAUDE.md，没有则警告。

**第五步：初始化 Ghostty helper**

准备阶段必须一次性初始化 helper 路径和 Ghostty 窗口 id，后续所有 phase 都复用同一个 helper 调用，不要每个阶段重新检测窗口，也不要重新实现 AppleScript。

原因：从 Claude Code / Codex 的 Bash tool 或后台子进程调用时，stdout 通常不是 tty，不能依赖 OSC title marker 定位当前 tab。必须在准备阶段取一次 Ghostty frontmost window id，然后通过 `bin/ghostty-open-tab --window-id` 显式传入。

输入法注意：`ghostty-open-tab` 会在创建新 tab 前先把 macOS 输入源切到 ABC，避免中文输入法把启动命令中的 `bash` 等字符转换成中文。不要通过 keystroke/粘贴方式向 Ghostty 输入启动命令；必须使用 helper 的 `command of cfg` 方式启动 run script。helper 会生成一个无空格路径的临时 launcher，并将 `command of cfg` 指向该 launcher，再由 launcher `exec` 真正的 run script，避免 Ghostty 对 `bash <script>` 参数拆分和中文输入法干扰。run script 内部的输入法切换只作为 agent 交互阶段的兜底，不负责启动命令阶段。

执行边界：
- helper 目录解析、provider CLI 解析、Ghostty window id 检测、run script 渲染都由 `bin/` 脚本或 `orchestrate.sh` 的薄封装完成。
- Ghostty window id 检测使用 `bin/detect-ghostty-window`；结果写入 workflow state metadata。
- provider CLI 必须解析成绝对路径；如 CLI 不在常见路径中，用户可通过 `CLAUDE_BIN` 或 `CODEX_BIN` 指定。
- `/workflow` skill 不维护 AppleScript 或 provider 命令细节；这些实现细节属于 `bin/ghostty-open-tab`、`bin/render-phase-run-script` 和 `bin/run-provider-noninteractive`。

## Phase 执行机制

每个阶段先从 workspace `workflow.json` 读取 `execution.order` 和 phase 配置，再按对应契约执行。以下是你作为编排器需要做的。

Workspace artifact 强校验由主编排器负责，不由阶段 agent 自己调用。每个阶段产物内容校验、latest 指针更新完成后，调用：

```bash
bin/validate-workspace-artifacts --manifest <workflow.json> --workspace <workspace>
```

失败时不要推进下一阶段；让当前阶段 agent 修正错误文件名、latest 指针或非法产物。该校验用于强制执行最终 plan 唯一命名、禁止 `fix-design.md` / `final-plan.md` / `plan-fix-rN.md`、review/fix 轮次连续和 latest 指针一致性。

### Execution Mode 判定

| Phase | Mode | 说明 |
|-------|------|------|
| review-requirement | Subagent phase | 需求审视，只写 `requirement-review.md` |
| explore | Interactive phase | 暂不子 agent 化，避免和 Claude 原生 Explore subagent 混淆 |
| design | Interactive phase | 需要用户和设计 agent 反复讨论 |
| review-plan | Subagent phase | 方案评审，只写 `review-rN.md` |
| revise | Interactive phase | 续接 design session 修正方案 |
| implement | Interactive phase | 需要长上下文和代码修改权限 |
| review-code | Subagent phase | 代码评审，只写 `code-review-rN.md` |
| fix | Interactive phase | 续接 implement session 修复代码 |
| verify-observability | Subagent phase | 可观测性验证，只写 `observability-report.md` |

### Step 1: 生成 prompt 文件

将阶段 prompt 写入 `<workspace>/<phase>/<phase>.prompt`。

**Skill 调用约定**：大部分阶段的 prompt 以"调用 /xxx skill"开头。Agent 收到此 prompt 后，应使用 Skill tool 调用对应 skill，然后按 skill 指引执行。Prompt 中的「上下文参数」覆盖 skill 中的默认路径（如 skill 默认写 workspace/plan.md，但上下文参数指定了 {dir_design}/plan.md，则以后者为准）。

### Step 1A: Subagent phase 执行契约

Subagent phase 不生成 run script，不打开 Ghostty tab，不写完成 marker。主 agent 直接用 Agent tool 派发独立子 agent。

Subagent prompt 必须包含：

```text
调用 /<skill> skill。

上下文参数：
...

执行模式：Subagent phase。
- 你是由 /workflow 主 agent 派发的独立分析子 agent。
- 直接完成任务并写入指定输出文件：<output_file>
- 不要等待用户确认，不要写 marker 文件。
- 不要修改业务代码；除指定报告/验证产物外不要写其他文件。
- 如需要读取代码，优先使用结构化索引、diff hunk、符号定位和小范围窗口读取，避免无边界全文件读取。
- 报告最后一行必须写 VERDICT，取值按对应 skill 要求。
- 完成后直接返回，简要说明产出文件路径。
```

主 agent 在子 agent 返回后必须：

1. 检查指定输出文件是否存在。
2. 读取报告末尾，确认 `VERDICT` 存在且取值合法。
3. 按对应 phase 的规则更新 latest 指针，例如 `cp review-rN.md review.md`。
4. 调用 `bin/validate-workspace-artifacts --manifest <workflow.json> --workspace <workspace>`。
5. 摘要关键发现给用户，并根据 VERDICT 决定继续、澄清、修正或修复。
6. 如果用户在主对话补充人工 CR 结果或裁定某个争议点，先判断是否影响最终方案事实；有影响则同步回 `design/plan.md`，必要时同步 `design/implementation-brief.md`，再推进下一阶段。
7. 如果子 agent 失败、报告缺失、VERDICT 缺失或 workspace artifact 校验失败，不推进下一阶段，先向用户报告缺口。

Codex fallback：如果没有 Agent tool，按以下顺序选择执行方式：
1. 优先使用 `bin/run-provider-noninteractive` 执行纯分析 phase，输入 prompt 文件，输出日志文件，由 phase prompt 约束只写指定报告。
2. 如果当前环境无法运行 provider CLI（认证、沙箱或权限问题），主 agent 可以在当前 session 直接执行该分析 phase，但必须把它当成隔离任务处理：只读必要上下文、只写指定报告、完成后立即回到主流程。
3. fallback 不能长期占用主上下文；不得把 review-code 的大范围文件阅读留在主 agent 后续上下文里继续使用。
4. 无论使用哪种 fallback，都必须按同一 artifact 校验、VERDICT 解析、latest 指针和 workflow-state 更新规则收尾。

### Step 1B: Interactive phase prompt 完成状态

Interactive phase 在 prompt 末尾追加完成状态指令：

```
重要：当你完成上述所有任务后，请告知用户你已完成，并列出你的产出文件路径，请用户审阅。
如果在与用户交流过程中，最终结论、边界、取舍、风险说明或修正内容发生变化，必须先把变化回写到当前阶段的输出文件对应章节，再结束对话；不要只在聊天里确认而不落盘。
当用户确认可以继续后（例如回复"ok"、"继续"、"下一步"等），运行以下 bash 命令写入阶段完成状态：
bin/workflow-state phase-finish --file "<workspace>/workflow-state.json" --phase "<phase_name>" --status done --exit-code 0 --output-file "<output_file>"
这个状态用于通知编排器推进到下一阶段。在用户明确确认之前，不要写入完成状态。
```

### Step 2: 生成 run script

仅 Interactive phase 生成 `<workspace>/<phase>/<phase>.run.sh>`。

通过 `bin/render-phase-run-script` 生成 `<workspace>/<phase>/<phase>.run.sh`。run script 必须：

- 切换到 `{project_dir}`
- 写入 `<workspace>/<phase>/<phase>.started`
- 输出 provider/model/project/session 信息
- 根据 provider 启动 agent CLI
- 如果 agent 退出但 phase 状态仍是 `running`，用 exit code 兜底写 `workflow-state.json`
- 写入后必须具备可执行权限，因为 `ghostty-open-tab` 的临时 launcher 会直接 `exec` run script，而不是通过 `bash <run_script>` 间接执行。

provider 命令细节由 `bin/render-phase-run-script` 负责。`<provider_cli>` 必须是 Phase 0.4 中解析到的绝对路径，不要在 run script 中直接写 `claude` 或 `codex`。

### Step 3: 开 Ghostty tab

仅 Interactive phase 开 Ghostty tab。

不要在 skill 中重新实现 AppleScript。必须调用 `bin/ghostty-open-tab`，并传入 Phase 0.4 中检测到的 `GHOSTTY_WINDOW_ID`，确保所有 interactive phase 复用同一个窗口。

```bash
open_phase_tab "<run_script_path>" "<project_dir>" "<started_marker>"
```

该脚本会先切换 ABC 输入源，再优先使用传入的窗口 id 开新 tab；未传入时 fallback 到 Ghostty frontmost window，最后才 fallback 到新窗口。started marker 用于验证启动成功。

### Step 4: 后台轮询等待

仅 Interactive phase 需要后台轮询等待 `workflow-state.json` 中的 phase status。用 Bash `run_in_background: true` 执行轮询脚本：

```bash
while [ "$(bin/workflow-state get-phase-status --file "<workspace>/workflow-state.json" --phase "<phase_name>")" = "running" ]; do sleep 5; done
echo "PHASE_COMPLETE:<phase_name>"
```

当后台任务完成时，你会收到通知。

### Step 5: 阶段间确认

Subagent phase 在子 agent 返回并通过产物检查后进入阶段间确认。Interactive phase 在后台任务完成后进入阶段间确认。在主对话中：

1. 读取产出文件，给用户一个简要摘要
2. 问用户是否继续下一阶段

如果用户说跳过、停止、或想调整，按指令操作。

### Step 6: 产出质量轻量校验

阶段完成后，不只检查文件是否存在，还要做最小内容校验。校验失败时不要推进下一阶段，先让对应阶段 agent 修正产物。

| Artifact | 必须校验 |
|----------|----------|
| `requirement-review/requirement-review.md` | 最后一行包含合法 `VERDICT: PASS` 或 `VERDICT: NEEDS_CLARIFICATION` |
| `design/plan.md` | 包含方案概述、复用分析、数据模型、接口设计、核心流程、性能评估、可观测性方案、实现指引、风险和待确认项、实施评估、设计决策记录、交付自检 |
| `design/implementation-brief.md` | 文件存在；包含 Required Changes、Contract Changes、Cross-repo Sync Points、Tests Required；所有条目应可回链到 plan section |
| `review/review-rN.md` | 包含评审详情和最后一行合法 `VERDICT: PASS` 或 `VERDICT: NEEDS_REVISION` |
| `implement/impl-notes.md` | 包含实现概要、方案符合度自检、测试覆盖情况、已知局限、plan.md / implementation-brief.md 同步情况、实现决策记录 |
| `review-code/code-review-rN.md` | 包含审查覆盖与缺口、Plan/Brief 同步要求，并在最后一行写合法 `VERDICT: PASS` 或 `VERDICT: NEEDS_FIX` |
| `review-code/fix-notes-rN.md` | 包含已修复、未修复及理由、plan.md 是否同步更新、implementation-brief.md 是否同步更新、测试运行结果 |
| `verify-observability/observability-report.md` | 包含静态验证结果、运行时验证结果或跳过原因，并有合法 VERDICT |

这是轻量校验，不替代 review-plan/review-code 的深度评审；它只防止空文件、漏章节、漏 VERDICT 之类的产物质量问题进入下一阶段。

## 各阶段 Prompt

### Phase 0.5: Review Requirement（默认开启，可跳过）

执行模式：Subagent phase。

```
调用 /review-requirement skill。

上下文参数：
- 需求文档：{workspace}/requirement.md
- 项目路径：{project_dir}（如有）
- 报告输出路径：{dir_requirement_review}/requirement-review.md
```

{requirement_review_context}：如果有项目路径，在 prompt 中加上 "项目代码在 {project_dir}，可以快速扫描验证需求的技术前提是否成立。"

**编排器在 review-requirement 完成后**：
1. 读取 requirement-review.md，检查 VERDICT
2. 如果 `VERDICT: PASS` → 告知用户审视通过，简要列出关键发现（如有扩展性建议），继续下一阶段
3. 如果 `VERDICT: NEEDS_CLARIFICATION` → 从报告的"必须澄清的问题"章节提取每一条，以**编号列表**形式展示给用户，格式如下：

```
需求审视发现以下问题需要你确认：

1. [问题内容]（来源：[维度名]）
2. [问题内容]（来源：[维度名]）
3. ...

请逐条回复你的决定（澄清/调整/忽略）。我会据此更新 requirement.md，然后继续进入设计阶段。
如果你想重新跑一次需求审视，也可以告诉我。
```

4. 收到用户回复后：
   - 将用户的澄清/调整写入 requirement.md（追加「需求澄清」章节，保留原文不删改）
   - 将用户标记为"忽略"的项记录到 requirement-review.md 末尾（标注"用户已确认忽略"）
   - 继续进入下一阶段（不重跑审视，除非用户明确要求）

**传递给后续阶段**：如果需求审视发现了值得注意的点（短视设计、扩展性建议等），在 design agent 的 prompt 中加上 "需求审视报告在 {dir_requirement_review}/requirement-review.md，请先阅读，其中的扩展性建议和边界澄清应纳入方案设计考虑。"

### Phase 1: Explore（可选）

执行模式：Interactive phase。当前不做子 agent 化。

```
调用 /explore skill。

上下文参数：
- 探索方向：{explore_input}
- 项目路径：{project_dir}
- 报告输出路径：{dir_explore}/exploration.md
如果探索过程中发现需求可以被细化，也将细化后的需求描述写入 {workspace}/requirement.md
```

### Phase 2: Design

执行模式：Interactive phase。

```
调用 /design skill。

上下文参数：
- 需求文档：{workspace}/requirement.md
- 项目路径：{project_dir}
- 方案输出路径：{dir_design}/plan.md
- 实现核对索引输出路径：{dir_design}/implementation-brief.md
- 交付要求：plan.md 是唯一权威设计与实现依据，必须完整到让新的 implement agent 不依赖历史对话即可实现。所有用户交互确认过的选择、边界、暂缓项、忽略项都必须写入 plan.md 对应章节；implementation-brief.md 只能从 plan.md 派生，不得包含 plan 外设计。
{design_context}
```

design_context：
- 如果有 exploration.md，加上 "探索报告在 {dir_explore}/exploration.md，请先阅读。"
- 如果有 requirement-review.md，加上 "需求审视报告在 {dir_requirement_review}/requirement-review.md，请先阅读，其中的扩展性建议和边界澄清应纳入方案设计考虑。"

### Phase 3: Review

执行模式：Subagent phase。

```
调用 /review-plan skill。

上下文参数：
- 方案路径：{dir_design}/plan.md
- 实现核对索引路径：{dir_design}/implementation-brief.md
- 项目路径：{project_dir}
- 报告输出路径：{dir_review}/review-rN.md（N 为当前轮次，如 review-r1.md）
- 评审要求：plan.md 是唯一权威设计与实现依据，implementation-brief.md 只是从 plan 派生的核对索引。必须检查 plan 是否足够让新 implement agent 独立实现，并检查 brief 是否完整覆盖 plan 且没有 plan 外内容。
{review_context}
```

review_context：第 2 轮起加 "这是第N轮评审。上一轮评审报告在 {dir_review}/review-r{N-1}.md，方案修正说明在 {dir_review}/revise-notes-r{N-1}.md。请重点验证上轮提出的问题是否已修正到位，同时检查修正是否引入新问题。"

**编排器在 review 完成后**：`cp review-rN.md review.md`（保持 review.md 始终指向最新版）

### Phase 3.5: Revise

执行模式：Interactive phase。

revise 从 `workflow-state.json` 读取 design 阶段的 `session_id`，按 provider 精确续接 design session。

```
评审报告已出，请根据评审反馈修正你的技术方案。

阅读评审报告：{dir_review}/review.md
{revise_context}

在 {project_dir} 项目中验证评审意见是否正确（自己读代码确认）。

决策确认规则：遇到以下情况必须暂停问用户：
- 评审意见和你的判断有分歧，需要用户裁定
- 修正方向有多种选择（如评审说"需要缓存"但你认为可以不加，或加不同类型的缓存）
- 修正会显著扩大方案范围
格式：🔀 [类型]: [问题] → 选项 A/B → 建议

修正规则：
- 评审意见正确的：修正方案
- 评审意见有误的：保留原方案，说明理由
- 评审建议合理但不在本次范围的：记录到风险章节

修正方式（三步走，禁止跳步）：

**第一步：影响分析（先想清楚再动手）**
- 先 `cp {dir_design}/plan.md {dir_design}/plan-rN.md`（N 为当前轮次，如 plan-r1.md）
- Read 完整的 plan-rN.md，理解全文结构
- 对每条评审意见，列出它影响的**所有章节**（不只是直接对应的章节）。例如：改数据模型字段 → 影响数据模型、接口设计、核心流程、性能评估、可观测性、实现指引共 6 处
- 将影响分析写入 revise-notes 的开头

**第二步：批量修改（按章节顺序，一次改到位）**
- 按方案的章节顺序从头到尾修改，不要在章节间跳来跳去
- 就地修改对应章节内容，禁止在文件末尾追加"修正说明"或"补充"章节
- plan-rN.md 必须是一份完整、自洽的方案文档，读起来像是一次性写出来的，而不是被打了补丁的
- 用 Edit 工具精确修改，不要 Write 重写整个文件

**第三步：全文一致性验证（强制执行）**
- Read 整个 plan-rN.md 通读一遍
- 逐项检查：数据模型中的字段名/类型是否与接口设计一致？流程步骤中引用的表名/方法名是否与定义一致？性能评估的数值假设是否与前文匹配？实现指引的路径/类名是否与正文对应？
- 如发现不一致，立即修正后再次通读确认
- 同步更新 {dir_design}/implementation-brief.md，确保 Required Changes、Contract Changes、Cross-repo Sync Points、Tests Required 与最新 plan-rN.md 一致
- 在 revise-notes 末尾记录一致性验证结论

将修正说明写入 {dir_review}/revise-notes-rN.md（N 为当前轮次，如 revise-notes-r1.md），包含：
- 采纳的评审意见及修正内容（标注修改了哪些章节）
- 未采纳的评审意见及理由
- 新增的风险项
- implementation-brief.md 的同步更新内容
- 与用户讨论中达成的决策（决策点 + 结论 + 理由）— 下游 agent 只读文件，读不到对话
```

**编排器在 revise 完成后**：`cp plan-rN.md plan.md`（保持 plan.md 始终指向最新版）

run script 按 provider 使用精确续接：Claude Code 使用 `--resume <session_id>`，Codex 使用 `codex resume <session_id>`。

续接来源：编排器从 `workflow-state.json` 读取目标 phase 的 `session_id`。`revise` 续接 `design`，`fix` 续接 `implement`。如果 `session_id` 缺失，Claude Code 可以回退到 session name，但可能出现同名 session 选择器；Codex 没有可靠 session name fallback，必须有 `session_id`。

### Phase 4: Implement

执行模式：Interactive phase。

```
调用 /implement skill。

上下文参数：
- 方案路径：{dir_design}/plan.md
- 实现核对索引路径：{dir_design}/implementation-brief.md
- 项目路径：{project_dir}
- 输出路径：{dir_implement}/impl-notes.md
{impl_context}
```

impl_context 构造规则：

`plan.md` 是唯一权威设计与实现依据。`implementation-brief.md` 是从 `plan.md` 派生出来的实现核对索引，用来防漏、定位和验收，不得引入 `plan.md` 没有的设计决策。历史评审和修正记录不传给 implement agent——如果 `plan.md` 无法让新 agent 独立实现，说明 design 交付不完整，应回到 design/revise 修 `plan.md`，而不是让 implement 靠对话历史或 brief 补洞。

`implementation-brief.md` 必须是短而精确的 checklist / trace index，控制在约 150-250 行。每个实现项都应能回链到 `plan.md` 的具体章节，包含：

```markdown
# Implementation Brief

## 1. Objective
## 2. Non-goals
## 3. Required Changes
| ID | Repo | File | Symbol | Change | Why | Verification |
## 4. Contract Changes
### API / Proto
### DB / Entity / Mapper
### Enum / Status
### Config / Job / MQ / Metrics
## 5. Cross-repo Sync Points
| Contract | Producer | Consumer | Must Match |
## 6. Edge Cases
## 7. Tests Required
| Test | Repo | Scenario | Expected |
## 8. Review Checklist
```

Implement agent 使用规则：
- 先读完整 `plan.md`，再读 `implementation-brief.md`。
- 以 `plan.md` 为唯一权威依据；brief 只用于核对实现项、contract、边界和测试是否遗漏。
- 如果 brief 与 plan 冲突，或 brief 提到 plan 中不存在的要求，不要按 brief 自行改代码；在 `impl-notes.md` 标记 `BLOCKED: brief/plan mismatch`，说明冲突，并暂停让编排器回到 design/revise 修正设计产物。
- 按 `Required Changes` 逐条从 `plan.md` 追溯并实现；每条在 `impl-notes.md` 标记 `DONE` / `SKIPPED` / `BLOCKED`。
- 如果实现过程中发现 `plan.md` 必须修改或补充，不要在 implement 阶段发明新设计；记录缺口并让编排器回到 design/revise。
- 不依赖历史对话；所有必须上下文来自文件。
- 读代码时遵守 hunk/window-first：先定位变更点和符号，再读小窗口，避免全量读取大文件。

编排器按以下规则拼接上下文：

1. **评审最终结论**（如有）：如果存在 `{dir_review}/review.md`（latest 指针），加上 "评审报告在 {dir_review}/review.md，可快速浏览了解评审关注的风险点，但实现以 plan.md 为准。"
2. **需求审视**（如有）：如果存在 `{dir_requirement_review}/requirement-review.md`，加上 "需求审视报告在 {dir_requirement_review}/requirement-review.md，其中的边界澄清和扩展性建议与实现相关。"

### Phase 5: Review Code

执行模式：Subagent phase。

```
调用 /review-code skill（对照方案模式）。

上下文参数：
- 方案路径：{dir_design}/plan.md
- 实现核对索引路径：{dir_design}/implementation-brief.md
- 项目路径：{project_dir}
- 报告输出路径：{dir_review_code}/code-review-rN.md（N 为当前轮次，如 code-review-r1.md）
- 审查要求：以 plan.md 为唯一权威依据；implementation-brief.md 只作为核对索引。不要只看 diff；必须从变更点扩展到调用方、被调方、测试、配置、数据模型、相似实现，并在报告中写明审查覆盖与缺口。必须检查 brief 是否完整覆盖 plan 中所有实现项，且没有新增 plan 外要求。
{review_code_context}
```

review_code_context：第 2 轮起加 "这是第N轮代码评审。上一轮评审报告在 {dir_review_code}/code-review-r{N-1}.md，修复说明在 {dir_review_code}/fix-notes-r{N-1}.md。请重点验证上轮提出的必须修改项是否已修复到位，同时检查修复是否引入新问题。"

**编排器在 review-code 完成后**：`cp code-review-rN.md code-review.md`（保持 code-review.md 始终指向最新版）

### Phase 5.5: Fix

执行模式：Interactive phase。

fix 从 `workflow-state.json` 读取 implement 阶段的 `session_id`，按 provider 精确续接 implement session。

```
代码评审报告已出，请根据评审反馈修复代码问题。

阅读评审报告：{dir_review_code}/code-review.md
实现核对索引：{dir_design}/implementation-brief.md
{fix_context}

在 {project_dir} 项目中修复评审指出的问题。

决策确认规则：遇到以下情况必须暂停问用户：
- 评审意见你认为有误，但不确定是否应该保留原实现
- 修复方式有多种选择，各有利弊
- 修复可能引入新的兼容性问题
- 人工 CR 或用户反馈改变了方案细节、边界、取舍或验证口径
格式：🔀 [类型]: [问题] → 选项 A/B → 建议

修复规则：
- 「必须修改」的问题：必须修复
- 评审意见有误的：保留原实现，说明理由
- 「建议改进」的问题：酌情采纳，不强制
- 修复或用户确认过程中产生的任何新事实，最终都必须同步回 {dir_design}/plan.md 对应章节；包括实现细节、异常处理、兼容策略、测试边界、可观测性口径、人工 CR 结论。
- 如果新事实影响 Required Changes、Contract Changes、Cross-repo Sync Points、Edge Cases、Tests Required 或 Review Checklist，同步更新 {dir_design}/implementation-brief.md，确保 brief 仍完全由 plan 派生。
- 如果当前 fix session 无法安全更新 plan.md，应暂停并让编排器回到 design/revise；不能只把最终事实写在 fix-notes。
- 如果 brief 与 plan 冲突，以 plan.md 为准；不要按 brief 发明新设计。冲突影响修复判断时，暂停让编排器回到 design/revise 修正设计产物。

修复后运行与本次变更相关的测试确保通过；如果项目没有测试、测试工具不可用，或本次变更不适合自动化测试，请在修复说明中写明原因和替代验证方式。

将修复说明写入 {dir_review_code}/fix-notes-rN.md（N 为当前轮次，如 fix-notes-r1.md），包含：
- 已修复的问题及修复内容
- 未修复的问题及理由（含与用户讨论达成的决策，下一轮 CR 会读此文件）
- plan.md 是否同步更新；如未更新，说明为什么这些变更不影响最终方案事实
- implementation-brief.md 是否同步更新；如未更新，说明原因
- 测试运行结果
```

fix_context：第 2 轮起加 "这是第N轮修复。上一轮修复说明在 {dir_review_code}/fix-notes-r{N-1}.md。"

run script 按 provider 使用精确续接：Claude Code 使用 `--resume <session_id>`，Codex 使用 `codex resume <session_id>`。

续接来源同 revise：优先读取 `workflow-state.json` 中 implement phase 的 `session_id`；Claude 可回退 session name，Codex 必须有 `session_id`。

### Phase 5.2: Verify Observability

执行模式：Subagent phase。

在 Code Review-Fix 循环 PASS 之后运行。

```
调用 /verify-observability skill。

上下文参数：
- 方案路径：{dir_design}/plan.md
- 项目路径：{project_dir}
- 报告输出路径：{dir_verify_obs}/observability-report.md
{verify_obs_deploy_context}
```

verify_obs_deploy_context：如果用户提供了部署环境信息，加 "代码已部署到 {env} 环境，应用名为 {app_name}。请使用 MCP 工具进行运行时验证。" 如果未部署则加 "代码尚未部署，跳过运行时平台验证，仅做静态代码检查。"

**编排器在 verify-observability 完成后**：
1. 读取 observability-report.md 的 VERDICT
2. 如果 PASS → 告知用户，进入汇总
3. 如果 NEEDS_FIX → 告知用户需要补充可观测性，列出必须补充的项目，让用户自行修复或回到 implement session 修

## Code Review-Fix 循环

代码评审完成后，编排器（你）需要：

1. 读取 code-review-rN.md，检查最后一行是否包含 `VERDICT: PASS` 或 `VERDICT: NEEDS_FIX`
2. 执行 `cp code-review-rN.md code-review.md`（保持 code-review.md 始终指向最新版）
3. 如果 PASS → 先确认 `design/plan.md` 和 `design/implementation-brief.md` 已包含 review/fix/manual CR 后的最终事实，再进入可观测性验证（Phase 5.2）
4. 如果 NEEDS_FIX → 告知用户评审发现问题，问是否进入修复
5. 修复完成后重新进入代码评审，循环直到 PASS

文件命名见「版本化产出命名规范」节。

## Design Review-Revise 循环

方案评审完成后，编排器（你）需要：

1. 读取 review-rN.md，检查最后一行是否包含 `VERDICT: PASS` 或 `VERDICT: NEEDS_REVISION`
2. 执行 `cp review-rN.md review.md`（保持 review.md 始终指向最新版）
3. 如果 PASS → 告知用户，问是否进入实现
4. 如果 NEEDS_REVISION → 告知用户评审发现问题，问是否进入修正
5. 修正完成后执行 `cp plan-rN.md plan.md`（保持 plan.md 始终指向最新版）
6. 重新进入评审，循环直到 PASS

文件命名见「版本化产出命名规范」节。

## 流程重入（需求变更）

如果用户在任意时刻说"需求改了，回到 design"、"重新跑"或类似指令：

1. 执行 Phase 0.4 第一步的归档流程（检查旧产出 → 归档到 `archive/round-N/` → 清空工作目录）
2. 从指定阶段重新开始，使用全新 session
3. 新 agent 的 prompt 中提供旧产出路径作为参考（`archive/round-N/design/plan.md` 等）

注意：归档逻辑已统一在 Phase 0.4 中，无论是首次运行发现旧产出还是用户显式要求重入，都走同一套归档流程。

## 注意事项

- **环境变量**：Ghostty `command` 模式不继承 shell 环境，必须在 run script 中显式 export
- **session 不自动退出**：agent 完成后 session 保持运行，用户可继续交流
- **Ghostty 必须**：此编排器依赖 Ghostty 1.3.0+ AppleScript API，其他终端不支持
- **项目约束检查**：启动前检查项目目录有无 `CLAUDE.md`/`AGENTS.md` 等 agent 指南，没有则警告
- **TRD 生成**：全流程完成后，提醒用户可用 `/write-trd` 将 plan.md 转为 TRD 文档
- **Shell 入口差异**：当前 `orchestrate.sh` 暂未接入 `review-requirement` 和 `verify-observability`，本次不补；`/workflow` skill 仍保留完整 phase 定义。
