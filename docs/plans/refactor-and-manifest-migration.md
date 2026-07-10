# j-workflow 修复与 Manifest 完全迁移计划

创建日期：2026-07-10。本文档是可执行的工作说明书：每个 Work Package（WP）都包含背景、目标、改动文件、具体步骤和验收标准，可以直接派给独立 agent 执行。执行任何 WP 前先读本文档的「全局不变量」和「执行顺序」。

## 全局不变量（所有 WP 都必须遵守）

1. `design/plan.md` 是唯一最终方案文件名，禁止引入 `final-plan.md`、`plan-final.md`、`plan-fix-rN.md`、`fix-design.md`。
2. 产物路径契约不变：`requirement.md`、`requirement-review/requirement-review.md`、`explore/exploration.md`、`design/plan.md`、`design/implementation-brief.md`、`review/review-rN.md` + `review/review.md`、`implement/impl-notes.md`、`review-code/code-review-rN.md` + `review-code/code-review.md`、`verify-observability/observability-report.md`。
3. VERDICT 机器可解析契约不变：报告最后一行 `VERDICT: <value>`，取值集合见根 `workflow.json` 各 phase 的 `verdicts`。
4. resume 语义不变：revise 续接 design 的 session_id，fix 续接 implement 的 session_id；Claude 可回退 session name，Codex 必须有 session_id。
5. 通用能力放 `bin/`，`orchestrate.sh` 只做编排；不要把 helper 能力内联回 orchestrate.sh。
6. 每个 WP 完成后必须跑「统一验证清单」（见文末），并更新 `CHANGELOG.md`。
7. 一个 WP 一次提交（或一组小提交），不要跨 WP 混改。

## 执行顺序与依赖

```
Phase A（独立 bug 修复，可并行）:  WP1  WP2  WP3  WP12
Phase B（共享能力补齐，可并行）:  WP4  WP5  WP6
Phase C（manifest 完全迁移，严格串行）:  WP7 → WP8 → WP9 → WP10
Phase D（改名，随时可做，建议最后做避免和 C 冲突）:  WP11
```

已完成（2026-07-10）：
- ✅ WP0：`parse_config` 不剥离行内注释导致示例配置把所有阶段静默关掉——已在 `orchestrate.sh` 的 `parse_config` 中加 `value="${value%%#*}"` 修复。
- ✅ `.gitignore` 已含 `.DS_Store`，无需处理。

---

## Phase A：Bug 修复

### WP1：CLI 参数优先级高于配置文件 ✅（2026-07-10）

**现状**：`orchestrate.sh` 先解析命令行参数，再 `parse_config`（约 522 行处），导致配置文件的值覆盖显式 CLI flag。只有 `provider` 用 `PROVIDER_FROM_CLI` 打了补丁，其余字段（`model`、`project_dir`、阶段开关、断点开关等）都是 config 赢。

**目标**：约定俗成的优先级：CLI > config 文件 > 内置默认值。

**改动文件**：`orchestrate.sh`、`README.md`（补一句优先级说明）、`workflow-config.example.yaml`（注释里说明会被 CLI 覆盖）。

**做法**：改成两遍解析，删掉 `PROVIDER_FROM_CLI` 补丁：

1. 第一遍：只扫描 `"$@"` 中的 `--config <file>`（一个简单 for 循环，不 shift 消耗参数）。
2. 找到则先执行 `parse_config`。
3. 第二遍：执行现有的完整 `while [[ $# -gt 0 ]]` 参数解析（CLI 天然覆盖 config 设的值）。`--config` 分支保留但改为 no-op（已在第一遍处理）。
4. 删除 `PROVIDER_FROM_CLI` 变量及 `parse_config` 中对它的判断。
5. `MODEL_FROM_USER` 语义保留（config 或 CLI 任一显式设置 model 都算 user 指定，用于 codex 默认模型探测），两处赋值逻辑不变。

**验收**：
- `--config cfg.yaml --model X`（cfg 里 `model: Y`）→ 生效的是 X。
- `--config cfg.yaml`（cfg 里 `provider: codex`，本机有 claude）→ 生效 codex。
- `--provider claude --config cfg.yaml`（cfg 里 `provider: codex`）→ 生效 claude。
- `bash -n orchestrate.sh` 通过。

### WP2：评审循环加轮数上限 ✅（2026-07-10）

**现状**：`review-plan → revise` 和 `review-code → fix` 都是 `while true` 直到 PASS。`--auto` 模式下断点全关，评审永不 PASS 时无限循环、无限烧 token。

**目标**：默认最多 3 轮；超限时安全停下，状态可 `--resume`。

**改动文件**：`orchestrate.sh`、`workflow-config.example.yaml`、`README.md`、根 `workflow.json`（可选，见下）。

**做法**：
1. 新增变量 `MAX_ROUNDS=3`，CLI 参数 `--max-rounds <n>`，config key `max_rounds`。
2. 两个循环开头（`REVIEW_ROUND=$((REVIEW_ROUND + 1))` 之后）检查：`if (( REVIEW_ROUND > MAX_ROUNDS ))`：
   - `--auto` 模式：`log_error "design-review 循环达到上限 ${MAX_ROUNDS} 轮仍未 PASS"`，写 `state_cmd set-workflow-meta --key loop_exhausted --value design-review`，`exit 2`。
   - 交互模式：调用 `wait_for_user` 风格的提问：继续再跑一轮 / 接受当前结果继续后续阶段 / 退出。选"继续"则临时放行本轮（`MAX_ROUNDS=$((MAX_ROUNDS+1))` 或等价逻辑）。
3. code-review-fix 循环同样处理（独立计数，共用同一个 `MAX_ROUNDS` 值即可）。
4. 根 `workflow.json` 若 WP8 尚未做，先不动 manifest；WP8 会把它落到 `loops.*.max_rounds`（见 WP8），届时 shell 读 manifest 值作为默认、CLI 覆盖。

**验收**：
- 构造一个永远输出 `VERDICT: NEEDS_REVISION` 的 stub provider（见 WP8 的 fake-provider，可提前建最小版），`--auto --max-rounds 2` 跑到第 3 轮进入前退出，exit code 2，`workflow-state.json` 中 `current_round` 为 2、`loop_exhausted` 已写。
- 正常 PASS 流程行为不变。

### WP3：断点选项语义统一 ✅（2026-07-10）

**现状**：`wait_for_user` 提供 Enter/q/s 三个选项，`s`（"跳过下一阶段"）在不同位置语义不一致：
- explore 后 `s` → 只关 design，但 review-plan 仍开着，会去评审不存在的 plan。
- review-plan 断点 `s` → 不 revise、退出循环、**同时关掉 implement**（orchestrate.sh 约 1105 行）。
- review-code 断点 `s` → 不 fix、结束循环。

**目标**：每个断点的选项明确、自解释，不出现"跳过 A 却隐式关掉 B"。

**改动文件**：`orchestrate.sh`（`wait_for_user` 及全部调用点）。

**做法**：
1. 重写 `wait_for_user`，参数化选项，返回选择字符串而不是 0/1：

```bash
# wait_for_user "<提示>" "<输出文件>" "<选项说明，如 'a=接受当前结果并继续后续阶段'>"
# 统一选项: Enter=继续推荐路径  a=接受当前结果跳过修正  q=保存状态并退出
```

2. 各调用点语义定义：

| 断点位置 | Enter | a | q |
|---|---|---|---|
| explore 后 | 进入 design | （无 a 选项） | 退出，产出保留 |
| design 后 | 进入 review-plan | 跳过方案评审，直接进 implement | 退出 |
| review-plan 出 NEEDS_REVISION 后 | 进入 revise | 接受当前 plan，退出循环，进 implement | 退出 |
| implement 后 | 进入 review-code | 跳过代码评审，直接结束 | 退出 |
| review-code 出 NEEDS_FIX 后 | 进入 fix | 接受当前代码，退出循环 | 退出 |

3. `q` 统一行为：打印"可用 --resume 继续"，exit 0，不再有的地方 exit 有的地方 break。
4. 删除 `s` 选项及"跳过下一阶段"的模糊表述；提示文案里写清 a 的具体走向（如 `a=接受当前方案并直接进入实现`）。

**验收**：逐个断点手动走一遍三个选项，行为与上表一致；`bash -n` 通过。

### WP12：解除默认模型硬编码

**现状**：`MODEL="claude-sonnet-4-6"` 写死在 `orchestrate.sh:52`，README、示例配置、`workflow/SKILL.md` 多处引用。模型下线时所有入口同时坏。

**目标**：Claude 侧默认不传 `--model`，用用户 Claude CLI 自己配置的默认模型；Codex 保持现有 `~/.codex/config.toml` 探测。只有用户显式指定时才传模型参数。

**改动文件**：`orchestrate.sh`、`bin/render-phase-run-script`、`bin/run-provider-noninteractive`、`README.md`、`workflow-config.example.yaml`、`workflow/SKILL.md`（0.1/0.3 节的模型描述）。

**做法**：
1. `orchestrate.sh`：`MODEL=""` 为初始值。claude 分支不再兜底具体型号；codex 分支保留 `detect_codex_default_model`（其内部兜底值 `gpt-5.5` 改为空亦可，保持现状也接受）。
2. `get_phase_model`：`$MODEL` 为空时返回空串。
3. `bin/render-phase-run-script` 和 `bin/run-provider-noninteractive`：`--model` 值为空时，生成的命令行**不包含**模型参数（claude 不加 `--model`，codex 不加 `-m/--model`）。检查这两个脚本当前的拼接逻辑，加 `if [[ -n "$MODEL" ]]` 守卫。
4. state 记录：模型为空时 `phase-start --model` 传 `provider-default` 字面量，便于事后审计。
5. 文档同步：把「Claude 默认 claude-sonnet-4-6」改为「Claude 默认使用 CLI 自身配置的模型」；示例配置里的具体型号仅作为示例保留并注明。

**验收**：
- 不带 `--model` 跑 claude：生成的 run script / 非交互命令里没有 `--model`；`workflow-state.json` 里 model 为 `provider-default`。
- `--model X`：命令里含 `--model X`。
- codex 不带 `--model`：仍读 config.toml。

---

## Phase B：共享能力补齐

### WP4：orchestrate.sh 接入归档逻辑（双入口共享）

**现状**：`workflow/SKILL.md` Phase 0.4 强制"发现旧产出先归档到 `archive/round-N/` 再清空"，逻辑以内联 bash 写在 skill 文档里；`orchestrate.sh` 完全没有归档，同名任务重跑会覆盖 `requirement.md` 并在旧产物上继续写。

**目标**：归档逻辑收敛为一个 `bin/archive-workspace` 脚本，两个入口共用。

**改动文件**：新建 `bin/archive-workspace`；`orchestrate.sh`；`workflow/SKILL.md`（Phase 0.4 第一步改为调用脚本）；`README.md`（bin 列表补一项）。

**做法**：
1. 新建 `bin/archive-workspace`（bash，风格对齐现有 bin 脚本）：

```
用法: archive-workspace --workspace <dir> [--check-only]
行为:
  1. 检测关键产出是否存在（design/plan.md、review/review.md、implement/impl-notes.md、
     review-code/code-review.md、requirement-review/requirement-review.md 任一存在即算有旧产出）
  2. --check-only: 有旧产出 exit 0 并打印 "has-artifacts"，无则 exit 1。不做任何修改。
  3. 默认模式: N = archive/round-* 目录数 + 1；把 requirement-review/ explore/ design/ review/
     implement/ review-code/ verify-observability/ 各目录内容、requirement.md、idea.txt、
     workflow.json、workflow-state.json 复制到 archive/round-N/（保留目录结构）；
     然后清空上述阶段目录和 workspace 根的 workflow.json / workflow-state.json。
  4. 输出归档目的地路径到 stdout。
```

2. `orchestrate.sh`：在 `state_cmd init` 之前（约 648 行前）插入：
   - `RESUME_MODE == true` → 跳过归档检查。
   - 否则 `bin/archive-workspace --check-only` 命中时：非 auto 模式询问用户（归档重来 / 改用 --resume / 退出）；auto 模式默认自动归档并 log。
3. `workflow/SKILL.md` Phase 0.4 第一步：删掉内联 bash 归档示例，改为"调用 `bin/archive-workspace --workspace <workspace>`，输出告知用户"。「流程重入」章节同样改为引用该脚本。

**验收**：
- 空 workspace 首跑：不归档。
- 有旧产出重跑（auto）：自动生成 `archive/round-1/`，工作目录清空，requirement.md 重新复制。
- 再跑一次：`archive/round-2/`，编号连续。
- `--resume`：不触发归档。
- `bin/validate-workspace-artifacts` 对归档后的 workspace 通过（确认它不把 `archive/` 内文件当违规，如有问题在 validate 脚本中排除 `archive/`）。

### WP5：交互阶段轮询加超时提示与手动解锁指引

**现状**：`run_phase` 里 `while status == running; do sleep 5; done` 无限等待。agent 忘记执行 `phase-finish`、或用户把 tab 撂着不管时，编排器永远挂起，用户也不知道怎么解锁。

**目标**：不自动放弃（交互阶段本来就可能很长），但周期性提示用户当前在等什么、以及手动解锁命令。

**改动文件**：`orchestrate.sh`（`run_phase` 轮询段，约 826-833 行）。

**做法**：
1. 轮询循环加计数器，每 60 次（约 5 分钟）打印一次：

```
[WAIT] 仍在等待 <phase> 完成（已等待 Xm）。
  - 如 agent 已完成但忘了写状态，可手动执行:
    <BIN_DIR>/workflow-state phase-finish --file <STATE_FILE> --phase <phase> --status done --exit-code 0 --output-file <output>
  - 如想放弃该阶段: 将 --status 改为 failed，编排器会退出并保留状态。
```

2. 新增可选 `--phase-timeout <minutes>`（默认 0 = 不超时）：超时后把 phase 标记为 `failed`（exit-code 124）并退出，提示 `--resume`。
3. 顺带检查：轮询前 `find-agent-session` 已有 30s 超时重试，不需要动。

**验收**：手动启动一个阶段不写完成状态，观察 5 分钟出现一次提示；按提示手动 `phase-finish` 后编排器正常推进；`--phase-timeout 1` 时 1 分钟后失败退出且 state 记录 failed。

### WP6：resume 判定升级为 state + 校验驱动

**现状**：`should_skip_phase` 只看输出文件是否存在。产物校验失败 exit 1 后输出文件仍在，`--resume` 会跳过恰恰有问题的阶段；而启动时的 `validate_workspace_artifacts` 又会因同一问题退出，恢复只能手工改文件。

**目标**：resume 依据 = state 中 phase 状态 + 产物内容校验，两者都过才跳过；循环阶段能恢复到正确轮次。

**改动文件**：`orchestrate.sh`。

**做法**：
1. `should_skip_phase` 改为三条件：
   - `state get-phase-status` ∈ {done, skipped}；
   - 输出文件存在；
   - `validate_phase_artifact` 通过（对无 verdict 的阶段只做关键词校验）。
   任一不满足 → 重跑该阶段（log 说明原因）。
2. 循环恢复：进入 review 循环前，若 `RESUME_MODE`：
   - 读 `current_loop` / `current_round`；
   - 若 latest 报告存在且 `is-pass` → 跳过整个循环（现有逻辑保留）；
   - 若 latest 报告存在且 NEEDS_* 且对应轮次 fix/revise 产物不存在 → 从该轮的修正阶段继续（`REVIEW_ROUND` 初始化为 `current_round` 而不是 0）；
   - 若该轮修正产物已存在 → 从下一轮评审继续。
3. 启动时的 `validate_workspace_artifacts` 失败在 `RESUME_MODE` 下降级为 warning（打印违规项，继续跑，让后续阶段修复），非 resume 模式维持 fail-fast。
4. 确认 `state_cmd init` 在 resume 时不会清掉旧 phase 数据（现有实现用 `setdefault("phases")`，是保留的——加一行注释说明这是刻意的）。

**验收**：
- 场景 1：design 完成、review 未跑，`--resume` → 跳过 design（state=done + 校验过），从 review r1 开始。
- 场景 2：review r1 = NEEDS_REVISION、revise 未做，`--resume` → 直接进 revise r1。
- 场景 3：手工把 plan.md 清空成不含必需章节，`--resume` → design 被判定需要重跑。

---

## Phase C：Manifest 完全迁移（核心）

> 目标状态：`orchestrate.sh` 是一个**通用 phase 引擎**——读 workspace `workflow.json` 的 `execution.order`，逐个 phase 按 manifest 元数据执行；prompt、循环、断点、产物、verdict 全部由 manifest + 模板文件驱动；`workflow/SKILL.md` 不再复述任何 phase 契约，只描述编排器行为。改任何一个 phase 只需要改 manifest + 对应 prompt 模板。

### WP7：Prompt 模板抽取（消除三处重复）

**现状**：每个阶段的 prompt 在 `orchestrate.sh` heredoc 和 `workflow/SKILL.md`「各阶段 Prompt」里各写一遍，且已经漂移（SKILL.md 的 revise 有「三步走」和「决策确认规则」，shell 版没有；fix 的「决策确认规则」也只在 SKILL.md）。

**目标**：每个 phase 一份 prompt 模板文件，两个入口渲染同一份。

**改动文件**：新建 `prompts/` 目录；新建 `bin/render-prompt`（或给 `bin/workflow-manifest` 加子命令，二选一，建议独立脚本保持单一职责）；`orchestrate.sh`；`workflow/SKILL.md`；根 `workflow.json`。

**做法**：
1. 新建模板文件（内容以 **SKILL.md 版本为准**——它更完整；把 orchestrate.sh 版本独有的差异合并进去，逐段 diff 确认无丢失）：

```
prompts/
  review-requirement.md
  explore.md
  design.md
  review-plan.md
  revise.md
  implement.md
  review-code.md
  fix.md
  verify-observability.md
  _footer-interactive.md      # 现 run_phase 追加的完成状态指令（DONEEOF 段）
  _footer-subagent.md         # 现 SKILL.md Step 1A 的子 agent 执行契约
  _footer-noninteractive.md   # 现 run_analysis_phase 追加的非交互约束（PROMPTEOF 段）
```

2. 模板占位符统一用 `{token}` 语法（与 `workflow.json` naming.tokens 一致）。必需 token 清单：`{project_dir}` `{workspace_dir}` `{task_name}` `{phase_dir}` `{round}` `{output_file}` `{plan_file}` `{brief_file}` `{requirement_file}` `{review_latest}` `{code_review_latest}` `{context}`。上下文块（design_context / review_context / fix_context 等第二轮起才有的内容）由编排器拼好后通过 `{context}` 单一 token 注入，模板里不做条件逻辑。
3. 新建 `bin/render-prompt`：

```
用法: render-prompt --template <file> --footer <interactive|subagent|noninteractive|none> \
       --var key=value [--var ...] [--output <file>]
行为: 读模板，替换所有 {token}；发现未替换的 {token} 残留时报错 exit 1（防漏参）；
      按 --footer 追加对应 _footer-*.md（同样做变量替换）；输出到 stdout 或 --output。
```

4. 根 `workflow.json` 每个 phase 加字段 `"prompt_template": "prompts/<phase>.md"`；`bin/validate-workflow-manifest` 增加校验：enabled phase 的 prompt_template 文件必须存在。
5. `orchestrate.sh`：所有 heredoc prompt 替换为 `bin/render-prompt` 调用；`run_phase` 的 DONEEOF 追加段和 `run_analysis_phase` 的 PROMPTEOF 追加段删除（由 footer 承担）。
6. `workflow/SKILL.md`：「各阶段 Prompt」整章删除，替换为一小节：「阶段 prompt 一律用 `bin/render-prompt --template prompts/<phase>.md` 渲染，token 含义见根 workflow.json 的 naming.tokens；context 块拼接规则如下」+ 保留各 phase 的 context 拼接规则表（这是编排器行为，不是 prompt 内容）。

**验收**：
- 对每个 phase：迁移前后渲染出的 prompt 逐字符 diff，差异只能是「合并 SKILL.md 增强内容」这类**有意**变化，diff 结果贴在 PR 描述里。
- `render-prompt` 漏传 var 时报错。
- `bin/validate-workflow-manifest workflow.json` 通过。

### WP8：通用 phase 引擎（orchestrate.sh 重写主干）

**现状**：`execution.order` 只用来设置 5 个 shell 布尔开关；每个 phase 是一段手写代码块；两个循环、断点、transition 全部硬编码。新增/调整 phase 必须改 shell。

**目标**：主干变成"遍历 `execution.order` → 按 phase 元数据分发执行"，循环和断点也由 manifest 驱动。

**改动文件**：根 `workflow.json`（schema v3）、`bin/validate-workflow-manifest`、`bin/create-workflow-run`、`bin/workflow-manifest`、`orchestrate.sh`（主干重写）、`TODO.md`、`CHANGELOG.md`。

**做法**：

1. **Manifest schema v3**（`schema_version: 3`），新增：

```jsonc
{
  "loops": {
    "design-review": { "review_phase": "review-plan", "fixup_phase": "revise", "max_rounds": 3 },
    "code-review-fix": { "review_phase": "review-code", "fixup_phase": "fix", "max_rounds": 3 }
  },
  // 每个 phase 增加:
  //   "prompt_template": "prompts/<phase>.md"      (WP7 已加)
  //   "breakpoint_after": true|false               (对应现 BP_AFTER_* 默认值)
  //   "runner": "interactive" | "noninteractive"   (mode=subagent 的 phase 在 shell 侧
  //                                                 一律 runner=noninteractive；mode 字段
  //                                                 保留给 /jflow skill 判断用 Agent tool)
}
```

   `validate-workflow-manifest` 同步校验：loops 引用的 phase 存在、max_rounds 为正整数、breakpoint_after 为布尔、schema v2 仍然接受（向后兼容一版）。

2. **执行模型**（伪代码，`orchestrate.sh` 新主干）：

```
for phase_id in $(workflow-manifest execution-order --file "$FLOW_FILE" --kind order); do
    [phase 属于某 loop 的 fixup_phase] && continue     # fixup 只由循环内部触发
    loop_name=$(phase-get loop)
    if [[ -n $loop_name && $phase_id == $(loop 的 review_phase) ]]; then
        run_review_loop "$loop_name"                   # 见 3
    else
        run_single_phase "$phase_id"                   # 见 4
    fi
    maybe_breakpoint "$phase_id"                       # 读 breakpoint_after + CLI 覆盖
done
```

3. **`run_review_loop <loop>`**（通用化现有两个 while 循环）：
   - round 从 1（或 resume 恢复值）开始；
   - 渲染 review prompt（context 块按 round>1 规则拼接，规则数据放进 manifest 每个 loop 的 `recheck_context_template` 字段，或保留为 shell 里以 loop 名分发的两个小函数——**允许**保留这一处分发，因为它是行为而非契约）；
   - 跑 review phase（noninteractive runner）→ 校验产物 → `cp` latest 指针 → `transition`；
   - `continue` → break；`<fixup>` → 断点确认 → 跑 fixup phase（interactive，resume_from 按 manifest）→ latest 指针（revise 有 `cp plan-rN.md plan.md`，由 manifest `updates` 字段驱动：对每个含 `{round}` 的 updates 条目渲染后 cp 到不含 round 的目标）→ round++；
   - round > max_rounds → WP2 的超限行为。
4. **`run_single_phase <phase_id>`**：从 manifest 读 runner/output/artifact_check/resume_from/model_key，分发到现有 `run_phase`（interactive）或 `run_analysis_phase`（noninteractive）。这两个函数本身保留，参数全部来自 manifest 查询，不再有 per-phase 调用点。
5. **断点**：删除 `BP_AFTER_*` 五个变量；`--break/--no-break <phase>` 改为写入运行时覆盖 map（bash 关联数组），`maybe_breakpoint` 先查覆盖 map、再查 manifest `breakpoint_after`。`--auto` 仍然全跳。
6. **`create-workflow-run`**：透传 `--max-rounds`、`--break/--no-break` 覆盖，写进 run workflow 的 `execution` 节（`execution.breakpoints`、`execution.max_rounds`），运行期一律从 run workflow 读，CLI 只在生成 run workflow 时起作用（这样 `--resume` 也能拿到当初的断点配置）。
7. **删除**：`PHASE_EXPLORE` 等 5 个布尔开关（`--skip`/`--explore` 改为直接传给 `create-workflow-run` 的 enable/disable）；phase 专属代码块（约 965-1311 行）全部被通用主干替代。
8. **测试基建**（本 WP 必须一起交付）：
   - `tests/fake-provider`：一个可执行 bash stub，按 `FAKE_PROVIDER_SCRIPT` 环境变量指定的场景文件，向指定输出路径写符合关键词/VERDICT 契约的假产物后退出。支持场景：全 PASS、review 先 NEEDS_REVISION 后 PASS、永远 NEEDS_FIX。
   - `tests/smoke.sh`：用 `CLAUDE_BIN=tests/fake-provider` + `--auto` 跑三个场景，断言产物文件集合、latest 指针、`workflow-state.json` 关键字段、exit code。交互阶段在测试里以 noninteractive 方式跑（加一个内部环境变量 `JW_TEST_FORCE_NONINTERACTIVE=1`，仅测试用，README 不宣传）。

**验收**：
- `tests/smoke.sh` 三场景全绿。
- 与迁移前对同一 fake 场景的产物做 diff：文件名、latest 指针、state 字段完全一致（行为等价性证明）。
- `bin/validate-workflow-manifest` 对 v3 根 manifest 通过，对旧 v2 workspace run manifest 也通过。
- `--skip review-code`、`--explore`、`--break implement`、`--max-rounds 1` 各跑一遍 fake 场景验证开关仍有效。

### WP9：shell 入口补齐 review-requirement 和 verify-observability

**前置**：WP8 完成后，这两个 phase 都是 noninteractive runner，接入近乎免费。

**改动文件**：根 `workflow.json`、`orchestrate.sh`（少量）、`bin/create-workflow-run`、`README.md`、`TODO.md`。

**做法**：
1. 根 manifest：`execution.shell_order` 与 `skill_order` 合并为单一 `execution.default_order`，删除 `shell_excluded`（迁移完成后不再有两套 order）。
2. review-requirement 的 `NEEDS_CLARIFICATION` 处理（shell 语境）：打印报告中「必须澄清的问题」段落，`wait_for_user` 变体询问：用户在 `requirement.md` 手工补充后继续 / 忽略继续 / 退出。auto 模式下 NEEDS_CLARIFICATION 视为失败退出（需求不清不应全自动往下跑）。
3. verify-observability 排在 code-review-fix 循环 PASS 之后；`NEEDS_FIX` 时打印必须补充项并以非零码结束（或断点询问），不进入自动修复循环（与 SKILL.md 现行为一致）。
4. `--skip review-requirement` / `--skip verify-observability` 支持。
5. 更新 README「Shell entry note」和 TODO 中「Do not add ... until explicitly requested」条目（本计划即显式请求）。

**验收**：fake-provider 场景扩展：requirement-review PASS / NEEDS_CLARIFICATION 两分支、observability PASS / NEEDS_FIX 两分支，`tests/smoke.sh` 覆盖。

### WP10：SKILL.md 瘦身

**前置**：WP7、WP8 完成。

**目标**：`workflow/SKILL.md`（现 744 行）降到 ~300 行以内，只保留：编排器职责、subagent/interactive 判定表、workspace 准备（调 `bin/archive-workspace`）、run workflow 生成规则、每阶段完成后的检查动作（VERDICT、latest 指针、validate-workspace-artifacts）、context 拼接规则表、Codex fallback 规则、流程重入。

**删除/替换**：
- 「各阶段 Prompt」全部 prompt 正文 → 引用 `prompts/`（WP7 已做大半，本 WP 收尾）。
- 「版本化产出命名规范」的表格细节 → 引用根 `workflow.json` 的 naming/artifacts 字段，只保留「禁止的命名」黑名单（这是给 agent 的行为约束，值得留）。
- 「产出质量轻量校验」表 → 引用 manifest `artifact_check` + `bin/validate-artifact`。
- 归档内联 bash → 已在 WP4 替换为脚本调用。

**验收**：瘦身后让一个全新 agent 只读 SKILL.md + manifest + prompts 走一遍 /jflow 流程（可用 fake 场景），确认没有因删文档而丢失必要指令；行数 ≤ 350。

---

## Phase D：改名

### WP11：skill 改名 `/workflow` → `/jflow`

**范围决策**（已定）：只改 skill 名和文档；仓库名 `j-workflow`、workspace 目录 `.workflow/`、`workflow.json`/`workflow-state.json` 文件名**不改**（不与 Claude Code 原生功能冲突，改动收益低、破坏兼容）。

**改动文件**：`workflow/` 目录整体 `git mv workflow jflow`；`jflow/SKILL.md` frontmatter `name: jflow`；全仓引用更新。

**做法**：
1. `git mv workflow jflow`；frontmatter `name: workflow` → `name: jflow`，description 里自称同步改。
2. `grep -rn '/workflow' --include='*.md' --include='*.sh' .` 逐个更新为 `/jflow`（注意区分 `/workflow` skill 引用与 `.workflow/` 目录路径、`workflow.json` 文件名——后两者不改）。已知引用点：README（多处）、TODO.md、CHANGELOG.md 视情况、`docs/multi-agent-workflow-optimizations/README.md`、各阶段 SKILL.md 若有互相引用。
3. 删除/精简消歧文案：README「Claude Code note」三条中关于「native dynamic workflow ≠ 本项目 /workflow」的部分可精简为一句；SKILL.md「术语边界」段精简。
4. 若用户本机以 symlink 方式把本仓库 skill 目录挂到 `~/.claude/skills/`（或 Codex 对应目录），提示重新链接：完成后在最终报告里提醒用户执行相应 re-link。

**验收**：`grep -rn '"/workflow"\|/workflow skill\|调用 /workflow' .` 无残留（`.workflow/` 路径除外）；在 Claude Code 中 `/jflow` 可被识别调用。

---

## 统一验证清单（每个 WP 完成后执行）

```bash
bash -n orchestrate.sh
for f in bin/*; do head -1 "$f" | grep -q python && python3 -m py_compile "$f"; done
bin/validate-workflow-manifest workflow.json
tests/smoke.sh          # WP8 之后可用
git diff --check
```

外加该 WP 自身的验收标准。全部通过后更新 `CHANGELOG.md`（一行说明 + WP 编号），并在本文档的 WP 标题后标注 ✅ 和完成日期。
