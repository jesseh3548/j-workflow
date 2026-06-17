# Programming Specification: Code Comments

Focus on comments that affect contract understanding or maintenance, not template noise.

## Mandatory

- [ ] Public classes, public fields, and public methods follow the project documentation style, usually Javadoc.
- [ ] Interfaces and abstract methods document semantics, parameters, return values, and exceptions or error codes.
- [ ] If the project still requires author/date tags, new files should stay consistent. If the project has dropped that rule, do not block on it.
- [ ] Inline comments should sit above the code they explain and keep indentation aligned.
- [ ] Business enums, error codes, reason codes, and state values must explain their meaning.

## Recommended / Reference

- [ ] Keep class names, protocol names, product names, and technical keywords in their original English form.
- [ ] Update comments when behavior, parameters, return values, exceptions, or state transitions change.
- [ ] Deleted code should not remain commented out unless there is a temporary and documented reason.
- [ ] Comments explain intent, constraints, and non-obvious edge cases; they should not restate obvious code.
- [ ] TODO/FIXME comments need owner, date or tracking ticket, and must not be left on high-risk paths.
- [ ] Public contracts around money, state, permissions, idempotency, and compatibility deserve explicit documentation.
