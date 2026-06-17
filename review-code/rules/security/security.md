# Security Specification

## Mandatory

- [ ] User-owned pages, resources, and operations must enforce authorization.
- [ ] Never rely on client-side visibility as access control.
- [ ] User-sensitive data must be masked or removed from direct display, logs, exports, and API responses.
- [ ] User-provided SQL parameters must be validated or bound through safe parameter APIs.
- [ ] SQL string concatenation with user input is forbidden.
- [ ] All user input must be validated for type, length, range, enum membership, and business permission.
- [ ] User data rendered to HTML must be escaped or filtered to prevent XSS.
- [ ] Form and AJAX submissions need CSRF protection when the application uses cookie/session authentication.
- [ ] Resource-consuming operations such as SMS, email, phone calls, orders, payment, and verification codes need replay/frequency controls.

## Recommended / Reference

- [ ] User-generated content such as posts, comments, and messages should go through anti-abuse, anti-scam, or risk-control filters.
- [ ] Validate page size, sort fields, redirect URLs, serialized payloads, regex input, and file paths as explicit security surfaces.
- [ ] Avoid logging tokens, credentials, full card numbers, personal identifiers, and raw request bodies that may include secrets.
- [ ] Permission checks should be close to the operation they protect, not only in an upstream controller.
- [ ] Error messages should not reveal internal class names, SQL, stack traces, or security policy details to external users.
- [ ] Deserialization input must be constrained by type, source, size, and trust boundary.
- [ ] Regex validation on user-controlled input must avoid catastrophic backtracking.
