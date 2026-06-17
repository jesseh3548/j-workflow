# Programming Specification: Flow Control Statements

## Mandatory

- [ ] Each `switch` case must end explicitly with `break`, `return`, `throw`, or a documented fall-through.
- [ ] Every `switch` must include `default`, even when it intentionally does nothing.
- [ ] `if`, `else`, `for`, `do`, and `while` statements must use braces.
- [ ] Avoid `if-else` nesting deeper than three levels. Use guard clauses, extracted methods, strategies, or state machines.

## Recommended / Reference

- [ ] Prefer guard clauses to reduce `else` branches and make the main path visible.
- [ ] Extract complex boolean expressions into named variables or methods.
- [ ] Avoid repeated heavy object creation, connection acquisition, or broad try-catch blocks inside loops.
- [ ] Batch operations must validate input size, page size, IN-list size, and per-run processing limits.
- [ ] Validate parameters for public APIs, RPC/HTTP entry points, permission-sensitive paths, expensive methods, and stability-critical methods.
- [ ] Private methods and hot inner loops may rely on caller validation only when the call chain makes that clear.
- [ ] State transitions must handle illegal states, duplicate requests, out-of-order requests, concurrent requests, and idempotency.
