---
name: workflow
description: "多 Agent 编排器。根据用户的需求，在 Ghostty 新 tab 中启动独立 Claude Code 或 Codex agent session 执行各阶段（需求审视→设计→评审→修正→实现→代码评审），每个阶段完成后回到主对话确认再推进。"
argument-hint: "[需求描述或飞书链接]"
allowed-tools: ["Read", "Write", "Bash", "AskUserQuestion", "Skill", "Glob", "Grep", "Agent"]
---

# Workflow — 多 Agent 编排器

你是编排器。你在 Claude Code 或 Codex 主对话中运行，通过 Ghostty 新 tab 启动独立 agent session 执行各阶段任务。

## 核心流程

```
主对话（你 = 编排器）
  │
  ├── 1. 理解需求 → 确认参数
  ├── 2. 准备 workspace
  │
  ├── 2.5 启动 review-requirement agent（Ghostty 新 tab）
  │     ├── 审视需求合理性（逻辑矛盾、边界模糊、可扩展性、外部知识验证）
  │     ├── 检查 VERDICT → NEEDS_CLARIFICATION 时暂停等用户澄清
  │     └── PASS 后继续
  │
  ├── 3. 启动 design agent（Ghostty 新 tab）
  │     ├── Bash run_in_background: 轮询 .done
  │     ├── 用户在 tab 内和 agent 交互
  │     ├── agent 完成 → 用户确认 → agent 写 .done
  │     └── 后台任务完成 → 通知回到主对话
  ├── 4. 问用户：要继续进入评审吗？
  │
  ├── 5. 启动 review agent（Ghostty 新 tab）
  │     └── ... 同上
  ├── 6. 检查 VERDICT → 如需修正 → 启动 revise agent
  │
  ├── 7. 启动 implement agent
  ├── 8. 启动 review-code agent
  ├── 9. 检查 VERDICT → 如需修复 → 启动 fix agent（循环）
  ├── 10. 启动 verify-observability agent
  └── 11. 汇总产出
```

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

每轮结束后，编排器执行 cp 保持 latest 指针更新：

| 指针文件 | 更新时机 | 命令 |
|----------|----------|------|
| `review/review.md` | review 完成后 | `cp review-rN.md review.md` |
| `design/plan.md` | revise 完成后 | `cp plan-rN.md plan.md` |
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
- **模型** — Claude 默认 claude-sonnet-4-6；Codex 默认读取 `~/.codex/config.toml`，读不到时使用 gpt-5.5；复杂需求可按 provider 选择更强模型

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
3. **模型** — 按 provider 选择。Claude Code 可选 Sonnet（默认）/ Opus；Codex 可选本机默认模型（读取 `~/.codex/config.toml`）/ 指定模型（如 `gpt-5.5`）
4. **是否需要需求审视** — 默认开启。需求来源是飞书 PRD 或口述时建议开启；需求已经过充分讨论且边界清晰时可跳过
5. **是否需要探索阶段** — 仅当需求文档中代码定位不够明确时

可根据上下文省略已明确的选项。

### 0.4 准备 workspace

**第一步（强制）：检查旧产出并归档**

在创建或写入任何文件之前，必须先检查 workspace 是否已存在产出：

```bash
# 检查 workspace 是否已存在
ls <project>/.workflow/<需求名>/design/plan.md 2>/dev/null
ls <project>/.workflow/<需求名>/review/review.md 2>/dev/null
ls <project>/.workflow/<需求名>/implement/impl-notes.md 2>/dev/null
```

如果任意产出文件已存在：
1. 确定当前是第几轮（检查 `archive/round-*` 目录数量，+1 即为当前轮次）
2. 将所有阶段目录中的文件复制到 `archive/round-N/` 下（保留目录结构）
3. 将当前 `requirement.md` 也归档
4. 清空所有阶段工作目录
5. 告知用户："检测到旧产出，已归档到 archive/round-N/"

```bash
# 归档示例
WORKSPACE="<project>/.workflow/<需求名>"
N=$(ls -d "$WORKSPACE/archive/round-"* 2>/dev/null | wc -l | tr -d ' ')
N=$((N + 1))
mkdir -p "$WORKSPACE/archive/round-$N"/{requirement-review,design,review,implement,review-code,verify-observability,explore}
cp "$WORKSPACE/requirement-review/"* "$WORKSPACE/archive/round-$N/requirement-review/" 2>/dev/null
cp "$WORKSPACE/design/"* "$WORKSPACE/archive/round-$N/design/" 2>/dev/null
cp "$WORKSPACE/review/"* "$WORKSPACE/archive/round-$N/review/" 2>/dev/null
cp "$WORKSPACE/implement/"* "$WORKSPACE/archive/round-$N/implement/" 2>/dev/null
cp "$WORKSPACE/review-code/"* "$WORKSPACE/archive/round-$N/review-code/" 2>/dev/null
cp "$WORKSPACE/verify-observability/"* "$WORKSPACE/archive/round-$N/verify-observability/" 2>/dev/null
cp "$WORKSPACE/explore/"* "$WORKSPACE/archive/round-$N/explore/" 2>/dev/null
cp "$WORKSPACE/requirement.md" "$WORKSPACE/archive/round-$N/" 2>/dev/null
# 清空工作目录
rm -f "$WORKSPACE/requirement-review/"* "$WORKSPACE/design/"* "$WORKSPACE/review/"* "$WORKSPACE/implement/"* "$WORKSPACE/review-code/"* "$WORKSPACE/verify-observability/"* "$WORKSPACE/explore/"*
```

如果无旧产出，跳过此步。

**第二步：创建目录结构并复制需求文档**

```
<project>/.workflow/<需求名>/
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

**第三步：检查 CLAUDE.md**

检查项目目录是否有 CLAUDE.md，没有则警告。

**第四步：初始化 Ghostty helper**

准备阶段必须一次性初始化 helper 路径和 Ghostty 窗口 id，后续所有 phase 都复用同一个 `open_phase_tab` 函数，不要每个阶段重新检测窗口，也不要重新实现 AppleScript。

原因：从 Claude Code / Codex 的 Bash tool 或后台子进程调用时，stdout 通常不是 tty，不能依赖 OSC title marker 定位当前 tab。必须在准备阶段取一次 Ghostty frontmost window id，然后通过 `bin/ghostty-open-tab --window-id` 显式传入。

输入法注意：`ghostty-open-tab` 会在创建新 tab 前先把 macOS 输入源切到 ABC，避免中文输入法把启动命令中的 `bash` 等字符转换成中文。不要通过 keystroke/粘贴方式向 Ghostty 输入启动命令；必须使用 helper 的 `command of cfg` 方式启动 run script。run script 内部的输入法切换只作为 agent 交互阶段的兜底，不负责启动命令阶段。

```bash
# Resolve helper script. Source checkout layout uses ./bin; installed layout may
# put helper scripts beside orchestrate.sh or expose WORKFLOW_BIN_DIR explicitly.
if [ -n "${WORKFLOW_BIN_DIR:-}" ] && [ -x "$WORKFLOW_BIN_DIR/ghostty-open-tab" ]; then
    WORKFLOW_BIN_DIR="$WORKFLOW_BIN_DIR"
elif [ -x "./bin/ghostty-open-tab" ]; then
    WORKFLOW_BIN_DIR="$(pwd)/bin"
elif [ -x "./ghostty-open-tab" ]; then
    WORKFLOW_BIN_DIR="$(pwd)"
else
    echo "Cannot find ghostty-open-tab helper; set WORKFLOW_BIN_DIR or run from j-workflow checkout" >&2
    exit 1
fi

GHOSTTY_WINDOW_ID=$(osascript -e '
tell application "Ghostty"
    if (count of windows) > 0 then
        return id of window 1
    else
        return "not_found"
    end if
end tell
' 2>/dev/null || echo "not_found")
if [ "$GHOSTTY_WINDOW_ID" = "not_found" ]; then
    GHOSTTY_WINDOW_ID=""
fi

resolve_provider_cli() {
    provider_name="$1"
    binary_name="$provider_name"
    override=""
    case "$provider_name" in
        claude) override="${CLAUDE_BIN:-}" ;;
        codex) override="${CODEX_BIN:-}" ;;
        *) return 1 ;;
    esac

    if [ -n "$override" ]; then
        [ -x "$override" ] && printf '%s\n' "$override" && return 0
        echo "$provider_name CLI override is not executable: $override" >&2
        return 1
    fi

    command_path="$(command -v "$binary_name" 2>/dev/null || true)"
    if [ -n "$command_path" ] && [ -x "$command_path" ]; then
        printf '%s\n' "$command_path"
        return 0
    fi

    for candidate in \
        "/opt/homebrew/bin/$binary_name" \
        "/usr/local/bin/$binary_name" \
        "$HOME/.local/bin/$binary_name" \
        "$HOME/.npm-global/bin/$binary_name"; do
        [ -x "$candidate" ] && printf '%s\n' "$candidate" && return 0
    done

    return 1
}

PROVIDER_CLI="$(resolve_provider_cli "$PROVIDER")" || {
    echo "Cannot find $PROVIDER CLI. Set CLAUDE_BIN or CODEX_BIN to an absolute path." >&2
    exit 1
}

open_phase_tab() {
    phase_run_script="$1"
    phase_project_dir="$2"
    phase_started_marker="$3"

    if [ -n "$GHOSTTY_WINDOW_ID" ]; then
        "$WORKFLOW_BIN_DIR/ghostty-open-tab" \
            --script "$phase_run_script" \
            --cwd "$phase_project_dir" \
            --verify-file "$phase_started_marker" \
            --window-id "$GHOSTTY_WINDOW_ID"
    else
        "$WORKFLOW_BIN_DIR/ghostty-open-tab" \
            --script "$phase_run_script" \
            --cwd "$phase_project_dir" \
            --verify-file "$phase_started_marker"
    fi
}
```

## Phase 执行机制

每个阶段的执行都遵循相同的模式。以下是你作为编排器需要做的。

### Step 1: 生成 prompt 文件

将阶段 prompt 写入 `<workspace>/<phase>/<phase>.prompt`。

**Skill 调用约定**：大部分阶段的 prompt 以"调用 /xxx skill"开头。Agent 收到此 prompt 后，应使用 Skill tool 调用对应 skill，然后按 skill 指引执行。Prompt 中的「上下文参数」覆盖 skill 中的默认路径（如 skill 默认写 workspace/plan.md，但上下文参数指定了 {dir_design}/plan.md，则以后者为准）。

在 prompt 末尾追加完成标记指令：

```
重要：当你完成上述所有任务后，请告知用户你已完成，并列出你的产出文件路径，请用户审阅。
当用户确认可以继续后（例如回复"ok"、"继续"、"下一步"等），运行以下 bash 命令写入完成标记：
echo "0" > "<workspace>/<phase>/<phase>.done"
这个标记用于通知编排器推进到下一阶段。在用户明确确认之前，不要写入该标记。
```

### Step 2: 生成 run script

生成 `<workspace>/<phase>/<phase>.run.sh`。run script 必须：

- 切换到 `{project_dir}`
- 写入 `<workspace>/<phase>/<phase>.started`
- 输出 provider/model/project/session 信息
- 根据 provider 启动 agent CLI
- 如果 agent 退出但没有写 `.done`，用 exit code 兜底写 `.done`

provider 命令规则：

```bash
# Claude Code 新 session
"<provider_cli>" --model "<model>" --name "<session_name>" --add-dir "<project_dir>" --permission-mode default --verbose -- "$(cat '<prompt_file>')"

# Claude Code 精确续接
"<provider_cli>" --model "<model>" --session-id "<session_id>" --add-dir "<project_dir>" --permission-mode default --verbose -- "$(cat '<prompt_file>')"

# Codex 新 session
"<provider_cli>" -m "<model>" -C "<project_dir>" "$(cat '<prompt_file>')"

# Codex 精确续接
"<provider_cli>" resume -m "<model>" -C "<project_dir>" "<session_id>" "$(cat '<prompt_file>')"
```

`<provider_cli>` 必须是 Phase 0.4 中解析到的绝对路径，不要在 run script 中直接写 `claude` 或 `codex`。Ghostty 新 tab 中运行的是非交互 shell，不会加载用户 shell alias/profile；如 CLI 不在常见路径中，用户可通过 `CLAUDE_BIN` 或 `CODEX_BIN` 指定。

需要传递的环境变量按 provider 最小化处理。Claude/Bedrock 相关变量、OpenAI/Codex 相关变量、AWS 变量和 `HOME` 可按需注入 run script。

### Step 3: 开 Ghostty tab

不要在 skill 中重新实现 AppleScript，也不要直接手写 `bin/ghostty-open-tab ...`。必须调用 Phase 0.4 中初始化的 `open_phase_tab` 函数，确保所有阶段复用同一个 `GHOSTTY_WINDOW_ID`。

```bash
open_phase_tab "<run_script_path>" "<project_dir>" "<started_marker>"
```

该脚本会先切换 ABC 输入源，再优先使用传入的窗口 id 开新 tab；未传入时 fallback 到 Ghostty frontmost window，最后才 fallback 到新窗口。started marker 用于验证启动成功。

### Step 4: 后台轮询等待

用 Bash `run_in_background: true` 执行轮询脚本：

```bash
while [ ! -f "<done_marker>" ]; do sleep 5; done
echo "PHASE_COMPLETE:<phase_name>"
```

当后台任务完成时，你会收到通知。

### Step 5: 阶段间确认

后台任务完成后，在主对话中：

1. 读取产出文件，给用户一个简要摘要
2. 问用户是否继续下一阶段

如果用户说跳过、停止、或想调整，按指令操作。

## 各阶段 Prompt

### Phase 0.5: Review Requirement（默认开启，可跳过）

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

```
调用 /explore skill。

上下文参数：
- 探索方向：{explore_input}
- 项目路径：{project_dir}
- 报告输出路径：{dir_explore}/exploration.md
如果探索过程中发现需求可以被细化，也将细化后的需求描述写入 {workspace}/requirement.md
```

### Phase 2: Design

```
调用 /design skill。

上下文参数：
- 需求文档：{workspace}/requirement.md
- 项目路径：{project_dir}
- 方案输出路径：{dir_design}/plan.md
{design_context}
```

design_context：
- 如果有 exploration.md，加上 "探索报告在 {dir_explore}/exploration.md，请先阅读。"
- 如果有 requirement-review.md，加上 "需求审视报告在 {dir_requirement_review}/requirement-review.md，请先阅读，其中的扩展性建议和边界澄清应纳入方案设计考虑。"

### Phase 3: Review

```
调用 /review-plan skill。

上下文参数：
- 方案路径：{dir_design}/plan.md
- 项目路径：{project_dir}
- 报告输出路径：{dir_review}/review-rN.md（N 为当前轮次，如 review-r1.md）
{review_context}
```

review_context：第 2 轮起加 "这是第N轮评审。上一轮评审报告在 {dir_review}/review-r{N-1}.md，方案修正说明在 {dir_review}/revise-notes-r{N-1}.md。请重点验证上轮提出的问题是否已修正到位，同时检查修正是否引入新问题。"

**编排器在 review 完成后**：`cp review-rN.md review.md`（保持 review.md 始终指向最新版）

### Phase 3.5: Revise

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
- 在 revise-notes 末尾记录一致性验证结论

将修正说明写入 {dir_review}/revise-notes-rN.md（N 为当前轮次，如 revise-notes-r1.md），包含：
- 采纳的评审意见及修正内容（标注修改了哪些章节）
- 未采纳的评审意见及理由
- 新增的风险项
- 与用户讨论中达成的决策（决策点 + 结论 + 理由）— 下游 agent 只读文件，读不到对话
```

**编排器在 revise 完成后**：`cp plan-rN.md plan.md`（保持 plan.md 始终指向最新版）

run script 按 provider 使用精确续接：Claude Code 使用 `--session-id <session_id>`，Codex 使用 `codex resume <session_id>`。

### Phase 4: Implement

```
调用 /implement skill。

上下文参数：
- 方案路径：{dir_design}/plan.md
- 项目路径：{project_dir}
- 输出路径：{dir_implement}/impl-notes.md
{impl_context}
```

impl_context 构造规则：

plan.md 是实现的唯一设计依据。历史评审和修正记录不传给 implement agent——如果 plan 需要靠 revise-notes 才能理解，说明 plan 本身不够完整，应在 revise 阶段修 plan。

编排器按以下规则拼接上下文：

1. **评审最终结论**（如有）：如果存在 `{dir_review}/review.md`（latest 指针），加上 "评审报告在 {dir_review}/review.md，可快速浏览了解评审关注的风险点，但实现以 plan.md 为准。"
2. **需求审视**（如有）：如果存在 `{dir_requirement_review}/requirement-review.md`，加上 "需求审视报告在 {dir_requirement_review}/requirement-review.md，其中的边界澄清和扩展性建议与实现相关。"

### Phase 5: Review Code

```
调用 /review-code skill（对照方案模式）。

上下文参数：
- 方案路径：{dir_design}/plan.md
- 项目路径：{project_dir}
- 报告输出路径：{dir_review_code}/code-review-rN.md（N 为当前轮次，如 code-review-r1.md）
{review_code_context}
```

review_code_context：第 2 轮起加 "这是第N轮代码评审。上一轮评审报告在 {dir_review_code}/code-review-r{N-1}.md，修复说明在 {dir_review_code}/fix-notes-r{N-1}.md。请重点验证上轮提出的必须修改项是否已修复到位，同时检查修复是否引入新问题。"

**编排器在 review-code 完成后**：`cp code-review-rN.md code-review.md`（保持 code-review.md 始终指向最新版）

### Phase 5.5: Fix

fix 从 `workflow-state.json` 读取 implement 阶段的 `session_id`，按 provider 精确续接 implement session。

```
代码评审报告已出，请根据评审反馈修复代码问题。

阅读评审报告：{dir_review_code}/code-review.md
{fix_context}

在 {project_dir} 项目中修复评审指出的问题。

决策确认规则：遇到以下情况必须暂停问用户：
- 评审意见你认为有误，但不确定是否应该保留原实现
- 修复方式有多种选择，各有利弊
- 修复可能引入新的兼容性问题
格式：🔀 [类型]: [问题] → 选项 A/B → 建议

修复规则：
- 「必须修改」的问题：必须修复
- 评审意见有误的：保留原实现，说明理由
- 「建议改进」的问题：酌情采纳，不强制

修复后运行与本次变更相关的测试确保通过；如果项目没有测试、测试工具不可用，或本次变更不适合自动化测试，请在修复说明中写明原因和替代验证方式。

将修复说明写入 {dir_review_code}/fix-notes-rN.md（N 为当前轮次，如 fix-notes-r1.md），包含：
- 已修复的问题及修复内容
- 未修复的问题及理由（含与用户讨论达成的决策，下一轮 CR 会读此文件）
- 测试运行结果
```

fix_context：第 2 轮起加 "这是第N轮修复。上一轮修复说明在 {dir_review_code}/fix-notes-r{N-1}.md。"

run script 按 provider 使用精确续接：Claude Code 使用 `--session-id <session_id>`，Codex 使用 `codex resume <session_id>`。

### Phase 5.2: Verify Observability

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
3. 如果 PASS → 告知用户，进入可观测性验证（Phase 5.2）
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
