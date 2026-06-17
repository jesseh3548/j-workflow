# MySQL Rules: SQL Rules

## Mandatory

- [ ] Use `COUNT(*)`, not `COUNT(column)` or `COUNT(1)`, when counting rows.
- [ ] Understand `COUNT(DISTINCT ...)` and NULL behavior, especially for multiple columns.
- [ ] `SUM()` can return NULL. Guard aggregation results before unboxing or arithmetic.
- [ ] Use NULL-aware checks such as `IS NULL` or project SQL helpers; `= NULL` does not work.
- [ ] If paging logic runs a count first and count is 0, return without running the page query.
- [ ] Do not use database foreign keys or cascading updates in distributed/high-concurrency application schemas unless the project explicitly allows them.
- [ ] Stored procedures are not allowed in application-owned business logic.
- [ ] Before manual update/delete correction scripts, run a SELECT verification first.

## Recommended / Reference

- [ ] Avoid large IN lists; if unavoidable, keep the size bounded, commonly no more than 1000.
- [ ] Be careful with byte length vs character length for multilingual strings.
- [ ] Avoid TRUNCATE in application scripts because it bypasses normal transactional expectations.
- [ ] Review update/delete WHERE clauses for accidental broad writes.
- [ ] Review dynamic ORDER BY, LIMIT, and condition fragments as injection and slow-query surfaces.
- [ ] Avoid using SQL functions on indexed columns in WHERE clauses when it prevents index usage.
