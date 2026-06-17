# MySQL Rules: Table Schema

## Mandatory

- [ ] Boolean database columns use `is_xxx` naming and a compact numeric type such as unsigned tinyint.
- [ ] Java POJO boolean fields should not use the `is` prefix even when database columns do.
- [ ] Non-negative numeric columns use unsigned types when MySQL is the storage engine.
- [ ] Table and column names use lowercase letters, digits, and underscores.
- [ ] Table and column names must not start with digits.
- [ ] Avoid identifiers that contain only digits between underscores.
- [ ] Table names are singular.
- [ ] Do not use MySQL reserved words such as `desc`, `range`, `match`, or `delayed` as identifiers.
- [ ] Index names follow project convention: primary key, unique key, and normal index should be distinguishable.
- [ ] Decimal values use `decimal`, not `float` or `double`.
- [ ] Fixed-length fields use `char` when appropriate.
- [ ] Very long `varchar` columns should be reconsidered; large text content should usually move to `text` or a separate table.
- [ ] Core tables should have an id primary key and creation/update timestamps unless the project has a clear alternative.
- [ ] Column comments must be updated when semantics or allowed status values change.

## Recommended / Reference

- [ ] Do not introduce sharding before data volume justifies it. The Alibaba baseline uses 5 million rows or 2GB as a review threshold, not an automatic trigger.
- [ ] Character set and collation choices must support the business domain.
- [ ] Use utf8mb4 when emoji or full Unicode is needed.
- [ ] Review whether schema changes require data migration, backfill, rollback scripts, or compatibility windows.
