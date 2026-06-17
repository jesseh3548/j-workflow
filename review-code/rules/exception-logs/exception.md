# Exception and Logs: Exception

## Mandatory

- [ ] Do not catch runtime exceptions such as `NullPointerException` or `IndexOutOfBoundsException` as normal handling; prevent them with checks.
- [ ] Do not use exceptions for normal flow control.
- [ ] Keep try-catch scopes precise. Separate stable code from code that can actually fail.
- [ ] Do not swallow exceptions. Either handle them fully or propagate them with context.
- [ ] Methods that throw exceptions inside transactions must preserve rollback semantics.
- [ ] Close resources in try-with-resources or finally.
- [ ] Finally blocks must not throw new exceptions that hide the original failure.
- [ ] Do not return from finally blocks because it can overwrite return values or swallow exceptions.
- [ ] Catch the narrowest useful exception type; avoid broad `Exception` unless the layer convention explicitly requires wrapping.
- [ ] Do not throw raw `RuntimeException`, `Exception`, or `Throwable` from business code. Use domain-specific exceptions or error results.
- [ ] If a method may return null, the contract must make that clear and callers must handle it.
- [ ] Cross-application RPC APIs should usually return a result object with success flag, error code, and message instead of relying on thrown exceptions.

## Review Hotspots

- [ ] Autounboxing nullable wrapper values.
- [ ] Null database query results.
- [ ] Collections that are non-empty but contain null elements.
- [ ] Null RPC responses or partially populated response objects.
- [ ] Session/context/map lookups.
- [ ] Chained access such as `a.getB().getC()` without intermediate guards.
- [ ] Exception translation across DAO, Manager, Service, Web, and Open Interface layers.
