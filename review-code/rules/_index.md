# Review Rule Index

This index routes code review to focused rule files. Read this file first, then load only the files that match the changed code and observed risks.

Baseline rule family: Alibaba Java Coding Guidelines. The rules below are reorganized for code review context management and include workflow-specific additions for tests, performance, and observability.

## Official Guideline Structure

- Programming Specification
  - `programming/naming.md`
  - `programming/constants.md`
  - `programming/formatting.md`
  - `programming/oop.md`
  - `programming/collections.md`
  - `programming/concurrency.md`
  - `programming/flow-control.md`
  - `programming/comments.md`
  - `programming/misc.md`
- Exception and Logs
  - `exception-logs/exception.md`
  - `exception-logs/logging.md`
- MySQL Rules
  - `mysql/schema.md`
  - `mysql/indexes.md`
  - `mysql/sql.md`
  - `mysql/orm.md`
- Project Specification
  - `project/layers.md`
  - `project/library.md`
  - `project/server.md`
- Security Specification
  - `security/security.md`
- Workflow-specific review additions
  - `workflow/testing.md`
  - `workflow/performance.md`
  - `workflow/observability.md`

## Routing Rules

| Change/Risk Area | Load |
|---|---|
| New/renamed classes, methods, fields, packages | `programming/naming.md` |
| Literal values, statuses, error codes, config keys | `programming/constants.md` |
| Readability-breaking style or formatter/checkstyle issues | `programming/formatting.md` |
| Interfaces, POJOs, inheritance, null handling, equals, serialization | `programming/oop.md` |
| Lists, maps, sets, arrays, iteration, de-duplication | `programming/collections.md` |
| Threads, pools, locks, ThreadLocal, shared state, async callbacks | `programming/concurrency.md` |
| Branches, loops, state machines, batch limits, input validation | `programming/flow-control.md` |
| Public contracts, enums, stale comments, TODO/FIXME | `programming/comments.md` |
| Regex, time, templates, dead code | `programming/misc.md` |
| try/catch, thrown errors, rollback, resources, null contracts | `exception-logs/exception.md` |
| Logger changes, missing context logs, sensitive logs | `exception-logs/logging.md` |
| DDL, table/column changes, column comments, character set | `mysql/schema.md` |
| New/changed indexes, join shape, pagination, EXPLAIN | `mysql/indexes.md` |
| SQL queries, updates, deletes, aggregation, NULL behavior | `mysql/sql.md` |
| Mapper XML, MyBatis/iBatis, resultMap, dynamic SQL | `mysql/orm.md` |
| Layer boundary, DO/DTO/BO/VO/Query leakage, module structure | `project/layers.md` |
| Dependency changes, library API, versioning, SNAPSHOT | `project/library.md` |
| Runtime/server behavior, redirects, file descriptors, JVM settings | `project/server.md` |
| Auth, sensitive data, injection, XSS, CSRF, replay controls | `security/security.md` |
| New behavior, bug fix, risky path, regression concern | `workflow/testing.md` |
| Latency, memory, throughput, IO loops, retries, large data | `workflow/performance.md` |
| Logs, metrics, alarms, tracing, async context | `workflow/observability.md` |

## Severity Guidance

- Blocking findings require a concrete code location, evidence, impact, and practical fix direction.
- Mandatory guideline violations can still be non-blocking if the project has an explicit conflicting convention and there is no real risk.
- Recommended/reference rules become blocking only when the current change creates correctness, compatibility, production, security, or maintainability risk.
- Do not output a full checklist. Use the loaded files to find real issues.
