# Workflow Review: Testing

Testing is not a direct Alibaba Java Coding Guidelines section, but it is required for this workflow's review quality.

## Coverage Expectations

- [ ] Core business behavior introduced or changed by the diff has tests.
- [ ] Boundary conditions are covered: null/empty input, invalid enum/status, duplicate request, out-of-order request, max batch size, permission denied, and downstream failure.
- [ ] Tests verify observable behavior, not only implementation details.
- [ ] Bug fixes include regression tests when the behavior is reproducible.
- [ ] Data-writing logic covers success, failure, rollback/compensation, and idempotency when relevant.
- [ ] API contract changes cover backward compatibility or versioned behavior.

## Test Quality

- [ ] Test names describe scenario and expected result.
- [ ] Assertions verify meaningful fields, not only non-null or no-exception.
- [ ] Mocks/stubs model important downstream behavior, including error responses.
- [ ] Fixtures do not hide the condition being tested.
- [ ] Time, randomness, and async behavior are controlled or made deterministic.

## Verification

- [ ] Run the smallest relevant test target when possible.
- [ ] If targeted tests are not available, run compile/typecheck/lint/module tests as the nearest signal.
- [ ] If tests cannot run, document the exact blocker and what static checks were performed.
- [ ] Missing tests are blocking only for high-risk core behavior such as money, state transitions, permissions, data writes, concurrency, or bug regression.
