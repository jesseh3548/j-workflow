
重要：当你完成上述所有任务后，请告知用户你已完成，并列出你的产出文件路径，请用户审阅。
如果你和用户交流后，最终结论、边界、取舍或修正有任何变化，必须先把这些变化回写到上述产出文件对应章节，再结束对话。
当用户确认可以继续后（例如回复"ok"、"继续"、"下一步"等），运行以下 bash 命令写入阶段完成状态：
"{bin_dir}/workflow-state" phase-finish-active --file "{state_file}" --status done --exit-code 0 --output-file "{output_file}"
这个状态用于通知编排器推进到下一阶段。在用户明确确认之前，不要写入完成状态。
