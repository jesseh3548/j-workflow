# 异常处理

- [ ] 不要 catch `NullPointerException`/`IndexOutOfBoundsException` 等运行时异常，用前置检查代替
- [ ] 禁止用异常做流程控制
- [ ] try-catch 范围要精确，区分稳定代码和非稳定代码
- [ ] 不要吞异常（catch 后空处理），要么处理要么重新抛出
- [ ] 抛异常的方法必须确保事务回滚
- [ ] 可关闭资源（stream、connection）必须在 finally 中关闭，或用 try-with-resources（JDK7+）；finally 块中不要抛异常
- [ ] finally 块中不要 return（会覆盖 try-catch 中的返回值或吞掉异常）
- [ ] catch 的异常类型必须是抛出类型的同类或父类，不要捕获过宽
- [ ] 不要直接抛 `RuntimeException`/`Exception`/`Throwable`，使用自定义业务异常（如 `DAOException`、`ServiceException`）
- [ ] 方法返回 null 时需在 Javadoc 中明确说明，调用方负责 null 检查
- [ ] 注意 NPE 高发场景：基本类型返回包装类拆箱、数据库查询结果为 null、集合元素为 null（即使 `isEmpty()` 为 false）、RPC 返回值为 null、Session 数据为 null、链式调用 `obj.getA().getB().getC()`（JDK8+ 用 `Optional` 避免）
- [ ] 跨应用 RPC 调用优先返回 Result 对象（含 isSuccess、errorCode、errorMessage），而非抛异常
