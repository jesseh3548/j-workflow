代码评审报告已出，请根据评审反馈修复代码问题。

阅读评审报告：{code_review_latest}
实现核对索引：{brief_file}
{context}

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
- 修复或用户确认过程中产生的任何新事实，最终都必须同步回 {plan_file} 对应章节；包括实现细节、异常处理、兼容策略、测试边界、可观测性口径、人工 CR 结论
- 如果新事实影响 Required Changes、Contract Changes、Cross-repo Sync Points、Edge Cases、Tests Required 或 Review Checklist，同步更新 {brief_file}，确保 brief 仍完全由 plan 派生
- 如果当前 fix session 无法安全更新 plan.md，应暂停并让编排器回到 design/revise；不能只把最终事实写在 fix-notes
- 如果 brief 与 plan 冲突，以 plan.md 为准；不要按 brief 发明新设计。冲突影响修复判断时，暂停让编排器回到 design/revise 修正设计产物

修复后运行与本次变更相关的测试确保通过；如果项目没有测试、测试工具不可用，或本次变更不适合自动化测试，请在修复说明中写明原因和替代验证方式。

输出格式硬性要求：
- fix-notes 必须包含以下精确中文关键词，否则编排器会判定失败：已修复的问题、未修复的问题、plan.md 是否同步更新、implementation-brief.md 是否同步更新、测试运行结果

将修复说明写入 {output_file}，包含：
- 已修复的问题及修复内容
- 未修复的问题及理由（含与用户讨论达成的决策，下一轮 CR 会读此文件）
- plan.md 是否同步更新；如未更新，说明为什么这些变更不影响最终方案事实
- implementation-brief.md 是否同步更新；如未更新，说明原因
- 测试运行结果
