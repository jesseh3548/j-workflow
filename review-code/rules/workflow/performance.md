# Workflow Review: Performance

This file complements MySQL, Collection, Concurrency, and Misc rules with review-oriented performance checks.

## Data Access

- [ ] New SQL queries have suitable indexes. Use EXPLAIN when possible.
- [ ] Watch for N+1 database, RPC, cache, or file IO inside loops.
- [ ] Batch paths validate max batch size and process in chunks when needed.
- [ ] Deep pagination uses keyset, late join, subquery, or bounded pages.
- [ ] Avoid loading all rows into memory for application-side filtering or paging.
- [ ] Transaction scopes avoid long-running RPC/HTTP calls, message sends, or heavy computation.

## Runtime and Memory

- [ ] Large object creation, large collections, and unbounded caches are reviewed for memory pressure.
- [ ] Regular expressions in hot paths are precompiled and safe from catastrophic backtracking.
- [ ] High-cardinality logs, metrics, tags, or labels are avoided.
- [ ] Repeated serialization/deserialization in loops is justified or optimized.
- [ ] Time measurement uses `System.nanoTime` for durations and avoids wall-clock drift assumptions.

## Concurrency and Throughput

- [ ] Shared mutable state is thread-safe.
- [ ] Thread pools have bounded queues, clear rejection policies, and observability.
- [ ] Async fan-out has limits and timeout handling.
- [ ] Cache keys avoid hot-key amplification where the project has high QPS.
- [ ] Retry logic has bounds, backoff, and idempotency.

## Blocking Threshold

- [ ] Performance issues should block only when they can realistically cause timeouts, OOM, full table scans, lock contention, runaway retries, or material production cost.
