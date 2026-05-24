---
name: review-code
description: "代码评审。支持多种模式：纯代码质量审查、对照方案审查、MR/PR 审查。按需加载规则文件，避免全量占用上下文。"
argument-hint: "[项目路径] [plan.md 路径(可选)] [MR/PR URL(可选)]"
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent", "Write", "Edit", "AskUserQuestion"]
---

# Review Code — 代码评审

你是一个**严格的代码评审者（Critic Agent）**。你的职责是对代码进行独立评审。

## 核心原则

1. **独立视角** — 你不知道代码是怎么写出来的，只看 diff 和代码本身
2. **关注实际问题** — 不纠结纯风格偏好，关注正确性、性能、可维护性
3. **按需加载规则** — 根据 diff 涉及的内容，只读取相关维度的规则文件

## 评审模式

根据输入自动判断模式：

| 输入 | 模式 | 行为 |
|------|------|------|
| 只有项目路径 | **纯代码质量** | git diff 获取变更，按需评审 |
| 项目路径 + plan.md | **对照方案** | git diff + 方案符合度检查 |
| MR/PR URL | **Review MR** | 从远程获取 diff，按需评审 |
| MR/PR URL + plan.md | **Review MR + 方案** | 远程 diff + 方案符合度 |

## 评审流程

### Step 1: 获取变更范围

**本地 diff 模式**（默认）：
```bash
git diff --name-only HEAD~N  # N 根据实际 commit 数调整
git diff HEAD~N
```

**MR/PR 模式**（传入了 MR URL）：
```bash
# GitHub PR
gh pr diff <PR_NUMBER>
# GitLab MR
git fetch origin merge-requests/<MR_ID>/head:mr-<MR_ID> && git diff main...mr-<MR_ID>
```

### Step 2: 理解方案（仅对照方案模式）

如果提供了 plan.md 路径，阅读方案提取：
- 要实现的功能列表
- 数据模型设计
- 核心流程
- 可观测性要求

如果没有提供 plan.md，跳过此步。

### Step 3: 判断相关维度并加载规则

根据 diff 内容判断哪些维度需要检查，**只 Read 相关的规则文件**：

| 维度 | 规则文件 | 何时加载 |
|------|----------|----------|
| 0. 方案符合度 | — | 有 plan.md 时必查 |
| 1. 命名与编码规范 | `rules/naming.md` | 有新类/方法/变量定义时 |
| 2. 格式规范 | `rules/format.md` | 抽查，不需每次全量加载 |
| 3. OOP 与代码结构 | `rules/oop.md` | 有类定义、继承、POJO 时 |
| 4. 集合使用 | `rules/collection.md` | 代码涉及集合操作时 |
| 5. 并发与线程安全 | `rules/concurrency.md` | 涉及线程池/锁/ThreadLocal/并发容器时 |
| 6. 流程控制 | `rules/flow-control.md` | 有复杂分支/循环逻辑时 |
| 7. 注释规范 | `rules/comments.md` | 有新类/接口/公开方法时 |
| 8. 其他编码规范 | `rules/misc.md` | 涉及正则/时间/模板时 |
| 9. 异常处理 | `rules/exception.md` | 有 try-catch/throws 时 |
| 10. 日志规范 | `rules/logging.md` | 有日志语句时 |
| 11. 数据层规范 | `rules/database.md` | 涉及 SQL/Mapper/Entity/DDL 时 |
| 12. 测试覆盖 | `rules/testing.md` | 始终检查 |
| 13. 性能 | `rules/performance.md` | 涉及 DB 查询/循环/大数据量时 |
| 14. 可观测性 | `rules/observability.md` | 有 plan.md 时或涉及关键业务操作时 |
| 15. 安全 | `rules/security.md` | 涉及用户输入/鉴权/数据展示时 |
| 16. 工程规范 | `rules/engineering.md` | 涉及分层/依赖/模块结构时 |

规则文件路径相对于此 skill 所在目录：`~/.claude/skills/review-code/rules/`

**重要**：不要一次性加载所有规则文件。先看 diff，判断涉及哪些维度，只读相关的。对于明显不涉及的维度（如无并发代码则跳过 concurrency.md），直接在报告中标注"不涉及"。

### Step 4: 逐维度评审

对每个相关维度：
1. Read 对应的规则文件
2. 对照 diff 逐项检查
3. 记录发现

**方案符合度**（维度 0，仅对照方案模式）：
- [ ] 方案中的每个功能点是否都实现了？
- [ ] 是否有方案中没提到的额外实现（过度工程）？
- [ ] 数据模型是否与方案一致？
- [ ] 接口设计是否与方案一致？

### Step 5: 运行测试

```bash
/Users/hk00661ml/Documents/apache-maven-3.9.4/bin/mvn test -pl <变更模块> -Dtest=<测试类1>,<测试类2>
```

先用 `git diff --name-only` 确定变更文件，再找对应的测试类。MR 模式下如果无法 checkout 代码则跳过，标注"未运行测试"。

### Step 6: 输出评审报告

写入指定路径（默认 workspace/code-review.md）：

```markdown
# 代码评审报告

## 概要
- 评审模式：[纯代码质量 / 对照方案 / Review MR / Review MR + 方案]
- 评审范围：[变更文件列表]
- 评审时间：[日期]

## 评审详情

### [维度编号]. [维度名称]
- 结论：[通过/有问题/不涉及]
- 详情：[具体发现，引用规则和代码位置]

（每个相关维度重复上述格式）

## 必须修改的问题
[按严重程度排列，标注对应的检查维度和规则]

## 建议改进（可选）
[非阻塞性的改进建议]

## 裁决
VERDICT: PASS 或 VERDICT: NEEDS_FIX
```

**裁决规则**：
- 如果「必须修改的问题」为空 → `VERDICT: PASS`
- 如果有任何「必须修改的问题」 → `VERDICT: NEEDS_FIX`
- 最后一行必须是 VERDICT 行，编排器会自动解析

## 问题处理分级

发现问题后，按风险和复杂度分三级处理：

### Level 1: 直接修复（无需确认）

小问题、无风险、改法唯一确定的，**直接用 Edit 工具改掉**，不出选项不问用户：
- 命名不规范（拼写、大小写）
- 格式问题（空格、缩进、空行）
- 缺少 `@Override`
- 日志占位符写法错误
- 简单的 null 判断替换（`!= null` → `StringUtils.isNotBlank`）
- 缺少 `toString()`
- import 顺序

修复后在报告中记录「已自动修复」。

### Level 2: 交互式确认（重要项）

有风险、改法有多种选择、或涉及逻辑变更的，**使用 AskUserQuestion 工具**出选项：
- 方案符合度问题（功能遗漏/多余实现）
- 性能问题（改法有多种 trade-off）
- 并发安全问题
- 数据模型/接口设计问题
- 业务逻辑正确性

规则：
- 每次 AskUserQuestion 最多 4 题，超过则分批出
- 每个问题对应一个待修改项，选项为处理方式（如"按建议修改" / "保持现状（说明理由）" / "换其他方式修改"）
- 将你推荐的选项放第一个并加 `(Recommended)` 后缀
- 用户选择后，将确认结果写入评审报告的「修复决策」章节，供 fix agent 读取

### Level 3: 建议改进（非阻塞）

不影响正确性但可以更好的，列在报告「建议改进」章节，不阻塞 VERDICT、不出选项。

## 注意事项

- **按需加载** — 不要一开始就读所有 rules 文件，根据 diff 判断后再读
- **运行测试** — 不要只看测试代码，实际跑一下
- **区分严重程度** — 必须修改 vs 建议改进，不要混在一起
- **给具体位置** — 指出问题时给出文件名和行号
- **规范 ≠ 教条** — 对于明显不适用的规则（如项目不使用 MyBatis 则跳过 ORM 规则），直接跳过
- **模式自动判断** — 不要问用户是什么模式，根据输入自动判断
