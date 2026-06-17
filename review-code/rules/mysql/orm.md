# MySQL Rules: ORM Rules

## Mandatory

- [ ] Query explicit columns; avoid `SELECT *`.
- [ ] Map database `is_xxx` boolean columns to Java fields without the `is` prefix.
- [ ] Do not return raw `resultClass` just because names match; use DO/resultMap or the project equivalent to decouple schema from objects.
- [ ] MyBatis/iBatis XML must use safe parameter binding (`#{}` or project equivalent), not string substitution (`${}`), for user data.
- [ ] Avoid old paging APIs that load all rows and then slice in memory.
- [ ] Do not use `HashMap` or `Hashtable` as query result types for business data.
- [ ] Updates must maintain `gmt_modified` or the project update timestamp convention.

## Recommended / Reference

- [ ] Do not define universal update methods that set every POJO field regardless of intended changes.
- [ ] Do not overuse `@Transactional`; assess QPS impact, rollback scope, cache/search/message compensation, and nested calls.
- [ ] Review dynamic SQL null/empty conditions carefully; absent fields must not unintentionally broaden updates or queries.
- [ ] Mapper result mappings must stay compatible with renamed columns, new columns, and removed columns.
- [ ] Batch insert/update mappers must have bounded batch size.
- [ ] Generated mapper code may need manual adjustment for boolean property mapping and result maps.
