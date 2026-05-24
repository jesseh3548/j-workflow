# 日志规范

- [ ] 使用 SLF4J 门面接口（`LoggerFactory.getLogger()`），不直接用 Log4j/Logback API
- [ ] 日志文件保留至少 15 天（部分异常按周出现）
- [ ] 扩展日志命名格式：`appName_logType_logName.log`（如 `mppserver_monitor_timeZoneConvert.log`），错误日志和业务日志分开存放
- [ ] TRACE/DEBUG/INFO 级别日志必须用占位符 `{}` 或条件输出（`if (logger.isDebugEnabled())`），禁止字符串拼接
- [ ] Logger 的 `additivity` 设为 false，防止日志重复和磁盘浪费
- [ ] 异常日志必须包含上下文信息和异常栈：`logger.error(contextInfo + "_" + e.getMessage(), e)`
- [ ] WARN 记录无效参数和数据追踪，ERROR 只记录系统逻辑错误和重要异常
- [ ] 注意日志量评估，高频路径避免打出海量日志
