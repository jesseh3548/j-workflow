调用 /implement skill。

上下文参数：
- 方案路径：{plan_file}
- 实现核对索引路径：{brief_file}
- 项目路径：{project_dir}
- 输出路径：{output_file}
- 实现上下文：{context}

执行规则：
- 先读完整 plan.md，再读 implementation-brief.md
- plan.md 是唯一权威设计与实现依据；implementation-brief.md 只作为从 plan 派生的核对索引
- 如 brief 与 plan 冲突，或 brief 提到 plan 中不存在的要求，不要按 brief 自行改代码；在 impl-notes.md 标记 BLOCKED: brief/plan mismatch，说明冲突，并暂停让编排器回到 design/revise 修正设计产物
- 按 plan 追溯并实现 brief 的 Required Changes，每条在 impl-notes.md 标记 DONE / SKIPPED / BLOCKED
- 如果实现过程中发现 plan.md 必须修改或补充，不要在 implement 阶段发明新设计；记录缺口并让编排器回到 design/revise
- 不依赖历史对话；所有必须上下文来自文件
- 读代码时遵守 hunk/window-first：先定位变更点和符号，再读小窗口，避免全量读取大文件
