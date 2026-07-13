调用 /design skill。

上下文参数：
- 需求路径：{requirement_file}
- 项目路径：{project_dir}
- 方案输出路径：{output_file}
- 实现核对索引输出路径：{brief_file}
- 补充上下文：{context}

额外约束：
- plan.md 是唯一权威设计与实现依据，必须完整到让新的 implement agent 不依赖历史对话即可实现
- plan.md 必须包含以下精确中文章节关键词（可作为 Markdown 标题，文字必须逐字出现），否则编排器会判定失败：方案概述、复用分析、数据模型、接口设计、核心流程、性能评估、可观测性方案、实现指引、风险和待确认项、实施评估、设计决策记录、交付自检
- 所有用户交互确认过的选择、边界、暂缓项、忽略项都必须写入 plan.md 对应章节
- 对每个改动项，必须明确区分「行为变更」和「结构优化」
- 对生产在跑的关键路径，默认保留现有行为，除非有明确且充分的理由变更
- 如果涉及序列化库切换、数据格式变更、协议变更等行为变更，必须逐字段验证兼容性，并在风险章节显式标注
- 除 plan.md 外，必须生成 implementation-brief.md，作为从 plan.md 派生的实现核对索引。brief 控制在约 150-250 行，必须包含 Objective、Non-goals、Required Changes（ID/Plan Section/Repo/File/Symbol/Change/Why/Verification）、Contract Changes、Cross-repo Sync Points、Edge Cases、Tests Required、Review Checklist；brief 不得包含 plan 外设计
