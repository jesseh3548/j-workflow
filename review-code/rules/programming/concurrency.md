# Programming Specification: Concurrency

## Mandatory

- [ ] Singleton initialization and singleton shared state must be thread-safe.
- [ ] Business code should use managed thread pools, not ad-hoc `new Thread`.
- [ ] Prefer explicit `ThreadPoolExecutor` or project wrappers over `Executors` defaults that can create unbounded queues or threads.
- [ ] Threads and thread pools must have meaningful names.
- [ ] `SimpleDateFormat` must not be shared as a static mutable instance. Use `DateTimeFormatter` or isolated instances.
- [ ] `ThreadLocal` values used with thread pools must be removed in `finally`.
- [ ] Lock granularity should be as small as practical.
- [ ] Lock acquisition order must be consistent when multiple resources are locked.
- [ ] `Lock.lock()` is called before the try block; unlock happens in `finally`.
- [ ] Concurrent updates to the same record require a defined locking or optimistic version strategy.
- [ ] Optimistic lock retry count must be bounded and large enough for the expected conflict rate.
- [ ] Use `ScheduledExecutorService` instead of `Timer` for scheduled work.

## Recommended / Reference

- [ ] Ensure `CountDownLatch.countDown()` runs even when worker code fails.
- [ ] Do not share a single `Random` across high-concurrency code; use `ThreadLocalRandom` when appropriate.
- [ ] Double-checked locking requires a `volatile` target field.
- [ ] `volatile` does not make compound operations atomic; use atomics or `LongAdder` for counters.
- [ ] Do not mutate a shared `HashMap` concurrently.
- [ ] `ThreadLocal` is for per-thread context, not shared-state updates.
- [ ] Async task submission should account for exception logging, timeout, rejection policy, context propagation, and cleanup.
