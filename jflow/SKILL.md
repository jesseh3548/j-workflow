---
name: jflow
description: "多 Agent 编排器。根据用户需求，由主 agent 编排子 agent 分析阶段和 Ghostty 交互阶段，完成需求审视→设计→评审→修正→实现→代码评审。"
argument-hint: "[需求描述或飞书链接]"
allowed-tools: ["Read", "Write", "Bash", "AskUserQuestion", "Skill", "Glob", "Grep", "Agent"]
---

# Jflow — 多 Agent 编排器

你是编排器。你在 Claude Code 或 Codex 主对话中运行，负责准备 workspace、派发阶段任务、检查阶段产物、决定是否推进下一阶段。

运行时根目录是包含本 `SKILL.md`、`bin/`、`prompts/`、`workflow.json` 的目录；开发态通常是仓库根，生产安装态是打包后的 `jflow/` skill 目录。运行脚本时先定位该 runtime root，并使用其中的 `bin/*`、`prompts/*` 和 `workflow.json`，不要假设当前项目 cwd 自带这些文件。

runtime root 的 `workflow.json` 是默认 phase manifest / 模板，记录阶段元数据、产物合同、模型 key、命名模板、verdict transition 和 resume policy。每次运行必须在 workspace 内生成一份同名 `workflow.json` 作为本次 run workflow；它根据用户需求和确认结果写入 `execution.order`，后续编排按 workspace `workflow.json` 推进，`workflow-state.json` 只记录实际运行状态并引用该文件。

脚本边界：通用能力必须放在脚本库 `bin/` 中，`orchestrate.sh` 只负责编排和调用。manifest 读取用 `bin/workflow-manifest`，manifest 校验用 `bin/validate-workflow-manifest`，state 写入用 `bin/workflow-state`，state 校验用 `bin/validate-workflow-state`，artifact 校验用 `bin/validate-artifact`，provider 非交互执行用 `bin/run-provider-noninteractive`，phase run script 渲染用 `bin/render-phase-run-script`。不要把这些能力重新内联进 `orchestrate.sh`。

阶段执行分两类：

| 模式 | 阶段 | 执行方式 | 适用原因 |
|------|------|----------|----------|
| Subagent phase | review-requirement / review-plan / review-code / verify-observability | 主 agent 使用 Agent tool 派发独立子 agent；子 agent 写报告后返回 | 纯分析/评审/验证，不需要长会话和用户在 tab 内交互 |
| Interactive phase | explore / design / revise / implement / fix | Ghostty 新 tab 中启动独立 agent session | 需要用户交互、长时间上下文、或精确 resume |

Codex 兼容规则：如果当前 Codex 运行环境没有可用的 Agent tool，不要强行模拟复杂子 agent。主 agent 可以按同一 prompt 在当前 session 直接执行该分析阶段，或使用已验证的非交互 CLI runner；但必须遵守同样的产物、VERDICT、只读/只写报告约束。

术语边界：本项目 `/jflow` skill 是 j-workflow phase orchestration。Claude Code 的 `/workflows` / `Run a dynamic workflow?` 是 Claude Code runtime 的原生 dynamic workflow 能力，两者不是同一个机制。看到 Claude 原生 dynamic workflow 弹窗，不代表 j-workflow 已进入 `.workflow/<name>/` 编排流程。

## 核心流程

默认顺序来自根 `workflow.json` 的 `execution.default_order`：review-requirement → explore → design → review-plan/revise loop → implement → review-code/fix loop → verify-observability → 汇总。每次运行以 workspace `workflow.json` 的 `execution.order` 为准，跳过项和断点只在生成 run workflow 时落盘。

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

## 产物命名规范

产物路径、latest 指针、轮次文件和 updates 均以根 `workflow.json` 为准，运行时必须调用 `bin/validate-workspace-artifacts` 校验。Agent prompt 中指定了输出文件时，必须严格写入该文件。

`design/plan.md` 是最终唯一权威方案文件；`plan-rN.md` 只用于 revise 中间产物和审计，不是下游输入。

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
- **模型** — 新建 Claude run 在参数确认前必须调用 runtime root 的 `bin/list-claude-models --format json` 实时读取当前 gateway 的 `/v1/models`；Codex 默认读取 `~/.codex/config.toml`，读不到时使用 gpt-5.5；复杂需求可按 provider 选择更强模型
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
3. **模型** — 按 provider 选择。Claude Code 必须在本次初始化时调用 `bin/list-claude-models --format json`，按 Opus / Sonnet / Haiku 分组展示实时结果；每个 family 在 gateway 提供足够候选时至少展示两个，版本号倒序，同版本优先 `us.` route。默认优先当前 `ANTHROPIC_MODEL`（前提是它存在于实时目录），否则使用 helper 标记的 `us.` 默认。不得使用 `ANTHROPIC_SMALL_FAST_MODEL` 作为主模型默认值。Codex 可选本机默认模型（读取 `~/.codex/config.toml`）/ 指定模型（如 `gpt-5.5`）
4. **是否需要需求审视** — 默认开启。需求来源是飞书 PRD 或口述时建议开启；需求已经过充分讨论且边界清晰时可跳过
5. **是否需要探索阶段** — 仅当需求文档中代码定位不够明确时
6. **是否需要阶段模型覆盖** — 默认不需要。复杂需求可让 design/review-plan/review-code 使用更强模型，implement/fix 使用默认模型。

可根据上下文省略已明确的选项。

Claude 模型目录规则：
- 每个新 run 的 Phase 0.3 都重新调用一次 helper，不复用上次结果，不把目录写入仓库、配置或缓存。
- helper 通过 `ANTHROPIC_BASE_URL` 或 `ANTHROPIC_BEDROCK_BASE_URL` 推导 gateway 根 `/v1/models`，并使用当前 `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` 鉴权。
- 若实时请求失败，只能把 `ANTHROPIC_MODEL` 作为明确标注的 fallback；不得退回代码内置模型列表，也不得伪造每个 family 的两个候选。
- 用户选定后只保存模型 ID；phase 执行不再次查询目录。
- `--resume` 不调用模型目录、不重新提问，必须复用 workspace run `workflow.json` 中已保存的 `provider` 和 `model`。

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

创建 `<project>/.workflow/<需求名>/`，包含 `workflow.json`、`workflow-state.json`、`requirement.md`、各 phase 目录（`requirement-review/`、`explore/`、`design/`、`review/`、`implement/`、`review-code/`、`verify-observability/`）和按需创建的 `archive/round-N/`。

**第三步：生成本次 run workflow**

从仓库根 `workflow.json` 读取默认 phase manifest，根据用户确认的阶段范围、provider、模型和跳过项，生成 `<workspace>/workflow.json`。Claude 使用 Phase 0.3 用户最终选中的完整模型 ID，不保存本次 gateway 目录。不要直接修改仓库根 `workflow.json`。

本次 run workflow 必须包含 `kind: "run"`、`source_manifest`、`task_name`、`provider`、`model`、`execution.order` 和 `execution.disabled`。

续跑时以 workspace run workflow 中的 `provider` 和 `model` 为准；忽略重新推断出的 provider 默认模型，也不要用当前环境中新出现的模型替换已保存选择。

初始化 `workflow-state.json` 后，必须将 `metadata.flow_file` 指向 `<workspace>/workflow.json`。需求中途变更时，旧的 workspace `workflow.json` 和 `workflow-state.json` 必须一起归档，再基于新需求生成新的 workspace `workflow.json` 和 state。

初始化 state 时还要调用 `bin/detect-main-agent-session` 识别当前主编排 agent。Claude Code 使用 `CLAUDE_CODE_SESSION_ID`，Codex 使用 `CODEX_THREAD_ID`；识别成功后通过 `bin/workflow-state set-main-agent` 写入顶层 `main_agent.provider`、`main_agent.session_id` 和 `main_agent.recorded_at`。主 agent provider 与 phase provider 是两个独立概念，不能用 run workflow 的 `provider` 代替。无法唯一识别时不猜测、不写错误 UUID，并明确提示。

**第四步：检查 CLAUDE.md**

检查项目目录是否有 CLAUDE.md，没有则警告。

**第五步：初始化 Ghostty helper**

准备阶段必须一次性初始化 helper 路径和 Ghostty 窗口 id，后续所有 phase 都复用同一个 helper 调用，不要每个阶段重新检测窗口，也不要重新实现 AppleScript。

原因：从 Claude Code / Codex 的 Bash tool 或后台子进程调用时，stdout 通常不是 tty，不能依赖 OSC title marker 定位当前 tab。必须在准备阶段取一次 Ghostty frontmost window id，然后通过 `bin/ghostty-open-tab --window-id` 显式传入。

输入法注意：`ghostty-open-tab` 会在创建新 tab 前切到 ABC，并通过 Ghostty `command of cfg` 启动一个无空格路径的临时 launcher，再由 launcher `exec` run script。不要用 keystroke/粘贴方式向 Ghostty 输入启动命令。

认证环境注意：Ghostty 通过 `command of cfg` 启动时不会加载用户的 `.zshrc` / `.bashrc`。不要手写裸 `claude` / `codex` Ghostty command 来启动 phase；否则容易丢失 `.zshrc` 中的 `ANTHROPIC_*` / `CLAUDE_CODE_*` 等鉴权变量。必须先用 `bin/render-phase-run-script` 渲染 run script，由 run script 显式 export 当前主进程中已有的 provider 鉴权环境，再交给 `bin/ghostty-open-tab` 启动。

环境变量边界：`ghostty-open-tab` 只负责打开 tab 和执行 run script，不得注入 provider 专属环境变量。尤其不要在 Ghostty launcher 层全局设置 `NODE_TLS_REJECT_UNAUTHORIZED=0`；该变量只允许由 provider 命令渲染脚本按 provider 条件处理，避免污染 Claude 启动环境。

执行边界：helper 目录解析、provider CLI 解析、Ghostty window id 检测、run script 渲染都由 `bin/` 脚本或 `orchestrate.sh` 薄封装完成。CLI 必须解析成绝对路径；如不在常见路径中，用户可用 `CLAUDE_BIN` 或 `CODEX_BIN` 指定。`/jflow` 不维护 AppleScript 或 provider 命令细节。

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

**Skill 调用约定**：大部分阶段的 prompt 以"调用 /xxx skill"开头。Agent 收到此 prompt 后，应使用 Skill tool 调用对应 skill，然后按 skill 指引执行。Prompt 中的「上下文参数」覆盖 skill 中的默认路径（如 skill 默认写 workspace/plan.md，但上下文参数指定了 `design/plan.md` 的绝对路径，则以后者为准）。

### Step 1A: Subagent phase 执行契约

Subagent phase 不生成 run script，不打开 Ghostty tab，不写完成 marker。主 agent 直接用 Agent tool 派发独立子 agent。

Subagent prompt 必须说明：调用对应 skill、执行模式为 Subagent phase、只写指定输出文件、不等待用户确认、不写 marker、不修改业务代码、优先用结构化索引/diff hunk/小窗口读取、最后一行写合法 `VERDICT`、完成后直接返回产出路径。

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

Interactive phase 在 prompt 末尾追加完成状态指令：完成后列出产物路径请用户审阅；如交流改变了结论、边界、取舍、风险或修正内容，先回写当前阶段输出文件；用户明确确认后才运行 `bin/workflow-state phase-finish-active --file "<workspace>/workflow-state.json" --status done --exit-code 0 --output-file "<output_file>"`。该命令从 state 的 `current_phase` 取得 canonical instance key，agent 不得自行传 phase 名称。

### Step 2: 生成 run script

仅 Interactive phase 生成 `<workspace>/<phase>/<phase>.run.sh>`。

通过 `bin/render-phase-run-script` 生成 `<workspace>/<phase>/<phase>.run.sh`。run script 必须：

- 切换到 `{project_dir}`
- 写入 `<workspace>/<phase>/<phase>.started`
- 输出 provider/model/project/session 信息
- 显式 export 当前主进程中的 provider 鉴权环境，不能依赖 Ghostty 加载 shell rc 文件
- 根据 provider 启动 agent CLI
- 如果 agent 退出但 phase 状态仍是 `running`，用 exit code 兜底写 `workflow-state.json`
- 写入后必须具备可执行权限，因为 `ghostty-open-tab` 的临时 launcher 会直接 `exec` run script，而不是通过 `bash <run_script>` 间接执行。

provider 命令细节由 `bin/render-phase-run-script` 负责。`<provider_cli>` 必须是 Phase 0.4 中解析到的绝对路径，不要在 run script 中直接写 `claude` 或 `codex`。Claude 分支不得额外注入 `NODE_TLS_REJECT_UNAUTHORIZED=0`；Codex 如需该变量，由 renderer 在 Codex 分支单独处理。

### Step 3: 开 Ghostty tab

仅 Interactive phase 开 Ghostty tab。

不要在 skill 中重新实现 AppleScript。必须调用 `bin/ghostty-open-tab`，并传入 Phase 0.4 中检测到的 `GHOSTTY_WINDOW_ID`，确保所有 interactive phase 复用同一个窗口。

```bash
open_phase_tab "<run_script_path>" "<project_dir>" "<started_marker>"
```

该脚本会先切换 ABC 输入源，再优先使用传入的窗口 id 开新 tab；未传入时 fallback 到 Ghostty frontmost window，最后才 fallback 到新窗口。started marker 用于验证启动成功。

### Step 4: 后台轮询等待

仅 Interactive phase 需要后台轮询等待 `workflow-state.json` 中的 phase status。用 Bash `run_in_background: true` 执行轮询脚本。轮询必须周期性提示当前等待的 phase 和手动解锁命令；如果用户配置了 `phase_timeout`，超时后要用 `bin/workflow-state phase-finish` 将 phase 标记为 `failed`、`exit-code 124`，再提示可用 `--resume` 继续。

```bash
while [ "$(bin/workflow-state get-phase-status --file "<workspace>/workflow-state.json" --phase "<phase_name>")" = "running" ]; do
  sleep 5
  # 每约 5 分钟提示:
  # bin/workflow-state phase-finish-active --file "<workspace>/workflow-state.json" --status done --exit-code 0 --output-file "<output_file>"
done
echo "PHASE_COMPLETE:<phase_name>"
```

当后台任务完成时，你会收到通知。

### Step 5: 阶段间确认

Subagent phase 在子 agent 返回并通过产物检查后进入阶段间确认。Interactive phase 在后台任务完成后进入阶段间确认。在主对话中：

1. 读取产出文件，给用户一个简要摘要
2. 问用户是否继续下一阶段

如果用户说跳过、停止、或想调整，按指令操作。

### Step 6: 产出质量轻量校验

阶段完成后，不只检查文件是否存在，还要按 `workflow.json` 的 `artifact_check` 调用 `bin/validate-artifact`，再调用 `bin/validate-workspace-artifacts`。校验失败时不要推进下一阶段，先让对应阶段 agent 修正产物。

## Prompt 模板与上下文

阶段 prompt 一律从仓库根目录的 `prompts/` 渲染，不在本 skill 中复写正文。渲染命令：

```bash
bin/render-prompt --template "prompts/<phase>.md" --footer "<interactive|subagent|noninteractive|none>" --var key=value ...
```

根 `workflow.json` 的每个 phase 通过 `prompt_template` 指向模板文件；`bin/validate-workflow-manifest` 会校验模板存在。模板占位符统一使用 `{token}`，由编排器传入：`project_dir`、`workspace_dir`、`task_name`、`phase_dir`、`phase_id`、`phase_name`、`round`、`output_file`、`requirement_file`、`plan_file`、`brief_file`、`review_latest`、`code_review_latest`、`context`、`bin_dir`、`state_file`。

footer 规则：
- Interactive phase 使用 `_footer-interactive.md`，包含用户确认后写 `workflow-state.json` 的完成命令。
- Subagent phase 使用 `_footer-subagent.md`，约束只写指定报告、直接返回。
- Shell noninteractive runner 使用 `_footer-noninteractive.md`，约束直接完成并退出。

context 拼接规则：
- `review-requirement`：如有项目路径，context 可提示快速扫描项目验证需求技术前提。
- `explore`：context 是探索输入；优先来自用户 idea，其次来自 `requirement.md`。
- `design`：如有 `explore/exploration.md`，context 加探索报告路径；如有 `requirement-review/requirement-review.md`，context 加需求审视报告路径。
- `review-plan`：第 2 轮起，context 加上一轮 `review-r{N-1}.md` 和 `revise-notes-r{N-1}.md`，要求重点验证修正是否到位并检查新问题。
- `revise`：第 2 轮起，context 加上一轮 `revise-notes-r{N-1}.md`；revise 续接 `design` session。
- `implement`：如有 `review/review.md`，context 加评审报告路径，但实现仍以 `plan.md` 为准；如有最新 `revise-notes-rN.md`，context 加修正说明路径。
- `review-code`：第 2 轮起，context 加上一轮 `code-review-r{N-1}.md` 和 `fix-notes-r{N-1}.md`，要求重点验证必须修改项是否已修复。
- `fix`：第 2 轮起，context 加上一轮 `fix-notes-r{N-1}.md`；fix 续接 `implement` session。
- `verify-observability`：如用户提供部署环境，context 加部署环境和应用名；否则提示只做静态代码检查。

阶段后动作仍由编排器负责：
- `review-plan` 完成后复制 `review-rN.md` 到 `review.md`。
- `revise` 完成后复制 `design/plan-rN.md` 到 `design/plan.md`。
- `review-code` 完成后复制 `code-review-rN.md` 到 `code-review.md`。
- 所有阶段完成后运行 artifact 校验；失败时不推进下一阶段。

## Review/Fix 循环

循环、transition、latest 指针和 updates 由 `workflow.json` 的 `loops`、phase `transitions`、`latest`、`updates` 定义。编排器负责执行 verdict 分支、复制 latest 指针，并在 review/fix/manual CR 改变事实时同步回 `design/plan.md` 和必要的 `design/implementation-brief.md`。

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
