# 性能

- [ ] SQL 查询是否有索引支持？（用 EXPLAIN 确认，目标 REF 级别以上）
- [ ] 是否有 N+1 问题？
- [ ] 循环内是否有 IO 操作（DB 查询、RPC 调用、文件操作）？
- [ ] 是否有大对象内存问题？
- [ ] 并发场景是否安全？（见 concurrency.md）
- [ ] 正则表达式是否预编译（`Pattern.compile` 不要放在方法体内）？
- [ ] 获取时间戳用 `System.currentTimeMillis()`，不用 `new Date().getTime()`
