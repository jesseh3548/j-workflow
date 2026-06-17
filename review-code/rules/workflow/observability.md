# Workflow Review: Observability

This file complements logging rules with workflow-specific observability review.

## Logs

- [ ] Critical business operations have logs with searchable business identifiers.
- [ ] Logs include enough context to reconstruct what happened without exposing sensitive data.
- [ ] Log levels match operational meaning: INFO for important lifecycle/business events, WARN for recoverable anomalies, ERROR for unexpected failures.
- [ ] Exception logs include stack traces and context.
- [ ] High-frequency paths avoid excessive logs and high-cardinality fields.

## Metrics and Alarms

- [ ] Custom metrics capture business semantics not already covered by framework metrics.
- [ ] Avoid duplicating framework-provided RPC/HTTP/DB/Kafka success rate and latency metrics unless there is a clear business dimension.
- [ ] Failure, rejection, timeout, compensation, and retry outcomes are observable on critical paths.
- [ ] New critical failure modes have an alarm strategy or an explicit reason why existing alarms cover them.

## Traceability

- [ ] Request IDs, order IDs, card IDs, user IDs, task IDs, message IDs, or other correlation fields are propagated where needed.
- [ ] Async boundaries such as MQ, scheduled jobs, and thread pools preserve enough context for troubleshooting.
- [ ] State transitions are traceable from request to persistence and downstream side effects.
