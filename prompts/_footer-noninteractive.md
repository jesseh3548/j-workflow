
重要：这是非交互 analysis phase。
- 必须直接完成任务并写入指定输出文件：{output_file}
- 不要等待用户确认
- 不要写 marker 文件或交互完成状态；非交互 runner 会在进程退出后更新 workflow-state.json
- 不要修改业务代码；除指定报告/验证产物外不要写其他文件
- 完成后直接退出
