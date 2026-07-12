调用 /review-code skill（对照方案模式）。

上下文参数：
- 方案路径：{plan_file}
- 实现核对索引路径：{brief_file}
- 项目路径：{project_dir}
- 报告输出路径：{output_file}
- 审查要求：以 plan.md 为唯一权威依据；implementation-brief.md 只作为核对索引。不要只看 diff；必须从变更点扩展到调用方、被调方、测试、配置、数据模型、相似实现，并在报告中写明审查覆盖与缺口。必须检查 brief 是否完整覆盖 plan 中所有实现项，且没有新增 plan 外要求。
- 评审上下文：{context}

最后必须给出一行总体裁决（这一行会被自动解析，格式必须严格）：
- 如果所有必须修改的问题都已解决或无必须修改项：VERDICT: PASS
- 如果有必须修改的问题：VERDICT: NEEDS_FIX
