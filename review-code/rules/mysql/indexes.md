# MySQL Rules: Index Rules

## Mandatory

- [ ] Business uniqueness must be protected with a unique index when the database is the source of truth.
- [ ] Joins should not exceed three tables.
- [ ] Join columns must have compatible types.
- [ ] Join columns must be indexed.
- [ ] Varchar indexes specify prefix length when appropriate.
- [ ] `LIKE '%x'` and `LIKE '%x%'` are not suitable for paged B-tree index queries; use search infrastructure when fuzzy search is required.

## Recommended / Reference

- [ ] Use composite index order to support both filtering and ordering.
- [ ] ORDER BY columns should align with the index tail when possible.
- [ ] Use covering indexes to avoid unnecessary table lookups.
- [ ] For deep pagination, use late join, keyset pagination, or subquery patterns instead of large offset scans.
- [ ] SQL optimization target: EXPLAIN should reach REF level when possible, RANGE at minimum for range queries, and CONST for unique lookups.
- [ ] Put highly selective equality columns early in composite indexes.
- [ ] Equality conditions usually precede range conditions in composite index design.
- [ ] Do not add one index per query blindly; assess read/write cost and index overlap.
- [ ] Do not rely on application-side "check then insert" as a replacement for unique indexes under concurrency.
