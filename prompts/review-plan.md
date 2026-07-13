调用 /review-plan skill。

上下文参数：
- 方案路径：{plan_file}
- 实现核对索引路径：{brief_file}
- 项目路径：{project_dir}
- 报告输出路径：{output_file}
- 评审上下文：{context}

输出格式硬性要求：
- 报告必须包含精确关键词：审查覆盖与缺口
- 最后一行必须是 VERDICT: PASS 或 VERDICT: NEEDS_REVISION

额外关注：
- plan.md 是唯一权威设计与实现依据，implementation-brief.md 只是从 plan 派生的核对索引
- 必须检查 plan 是否足够让新 implement agent 独立实现，并检查 brief 是否完整覆盖 plan 且没有 plan 外内容
- 必须提取并验证方案隐含假设：对 plan 中关于现有代码行为、复用点、异常传播、配置/枚举/状态存在性的描述逐条读源码验证
- 方案中标注为「行为变更」的改动，必须逐字段验证兼容性
- 如果方案没有区分行为变更和结构优化，这本身就是一个问题

最后必须给出一行总体裁决（这一行会被自动解析，格式必须严格）：
- 如果所有项都通过：VERDICT: PASS
- 如果有任何项需要修改：VERDICT: NEEDS_REVISION
