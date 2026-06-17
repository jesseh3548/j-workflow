# Project Specification: Server Specification

## Recommended / Reference

- [ ] High-concurrency services should account for TCP time-wait and file descriptor limits at deployment level.
- [ ] JVM services should have OOM dump settings where operationally appropriate.
- [ ] Internal redirects and external URL construction should use project-safe helpers.
- [ ] External redirects need validation to avoid open redirect vulnerabilities.
- [ ] Runtime configuration changes should include rollback strategy and observability.
- [ ] Changes that alter ports, threads, memory, connection pools, or timeouts must be reviewed with deployment environment constraints.
- [ ] Background jobs and scheduled tasks should have clear ownership, single/multi-instance behavior, and failure handling.
