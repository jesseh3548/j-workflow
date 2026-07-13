
重要：这是非交互 task phase。
- 必须直接完成任务并写入指定输出文件：{output_file}
- 不要等待用户确认
- 不要写 marker 文件或交互完成状态；非交互 runner 会在进程退出后更新 workflow-state.json
- 可以按本阶段 prompt、plan.md、implementation-brief.md 的要求修改项目文件
- 不要修改 workflow-state.json、workflow.json、prompt/log 文件或非本阶段要求的 workflow 产物；除指定输出文件和必要项目文件外不要写其他文件
- 完成后直接退出
