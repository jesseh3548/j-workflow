# 其他编码规范

- [ ] 正则表达式必须预编译（`Pattern.compile()` 不要放在方法体内）
- [ ] `Math.random()` 返回 double（0<=x<1），需要随机整数时用 `Random.nextInt()` 或 `Random.nextLong()`
- [ ] 获取时间戳用 `System.currentTimeMillis()`，不用 `new Date().getTime()`；精确计时用 `System.nanoTime()`；JDK8+ 用 `Instant`
- [ ] 如项目使用 Velocity 模板：属性直接用属性名引用（引擎自动调 getXxx），Boolean 包装类引擎调 getXxx 而非 isXxx；变量加 `$!{var}` 防止 null 直接显示
- [ ] 数据结构初始化时指定大小，避免无限增长导致内存问题
- [ ] 已确认废弃的代码和配置及时删除，不要留死代码
