# 并发与线程安全

- [ ] 单例初始化和内部方法必须线程安全
- [ ] 线程必须用线程池提供，禁止显式 `new Thread()`
- [ ] 线程池必须用 `ThreadPoolExecutor` 创建，禁止用 `Executors`（`FixedThreadPool`/`SingleThreadPool` 队列长度 `Integer.MAX_VALUE` 可能 OOM，`CachedThreadPool`/`ScheduledThreadPool` 线程数 `Integer.MAX_VALUE` 可能 OOM）
- [ ] 线程/线程池必须命名（方便排查问题）
- [ ] `SimpleDateFormat` 非线程安全，禁止定义为 static 变量（用 `ThreadLocal` 包装或用 JDK8 的 `DateTimeFormatter`）
- [ ] `ThreadLocal` 变量必须在 finally 中 `remove()`，防止线程池复用导致数据串和内存泄漏
- [ ] 高并发场景锁的粒度：块锁优于方法锁，对象锁优于类锁
- [ ] 多资源加锁顺序保持一致，防止死锁
- [ ] `lock()` 必须在 try 外面，且 `lock()` 和 try 之间不能有其他代码，确保 finally 中能正确 `unlock()`
- [ ] 并发修改同一记录用锁或乐观锁（version 字段），冲突率 <20% 用乐观锁，重试 ≥3 次
- [ ] 用 `ScheduledExecutorService` 替代 `Timer`（Timer 单线程异常会杀死所有任务）
- [ ] `CountDownLatch` 每个线程退出前必须调 `countdown`，注意子线程异常不会被主线程捕获
- [ ] 避免多线程共享 `Random` 实例（竞争同一 seed 影响性能），JDK7+ 用 `ThreadLocalRandom`
- [ ] 双重检查锁的对象声明为 `volatile`
- [ ] `count++` 操作用 `AtomicInteger`/`LongAdder`（JDK8+），不要依赖 volatile
- [ ] 高并发下 `HashMap` 扩容可能死链导致 CPU 100%，需注意线程安全
- [ ] `ThreadLocal` 对象建议用 `static` 修饰，所有操作共享同一实例
