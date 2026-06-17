# Exception and Logs: Logs

## Mandatory

- [ ] Use the project logging facade, normally SLF4J. Do not depend directly on Log4j/Logback APIs in business code unless the module owns logging infrastructure.
- [ ] Log retention should satisfy operational requirements. The Alibaba baseline mentions at least 15 days for many application logs.
- [ ] Extended business logs should follow the project naming convention and keep error logs separate from business/audit logs when applicable.
- [ ] TRACE/DEBUG/INFO logs should use `{}` placeholders or guarded logging, not eager string concatenation.
- [ ] Logger additivity and appender configuration should avoid duplicate logs and disk waste.
- [ ] Exception logs must include business context and the throwable object so stack traces are preserved.
- [ ] WARN is for invalid input, recoverable anomalies, or traceable business exceptions.
- [ ] ERROR is for system logic failures and important unexpected exceptions.
- [ ] High-frequency paths must account for log volume and cardinality.

## Review Hotspots

- [ ] Missing business identifiers that make production troubleshooting impossible.
- [ ] Sensitive data in logs.
- [ ] Logging only `e.getMessage()` without stack trace.
- [ ] Logging and rethrowing at multiple layers, causing duplicated noise.
- [ ] Error logs that lack enough context to reproduce or search the issue.
