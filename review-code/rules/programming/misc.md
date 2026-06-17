# Programming Specification: Other

## Mandatory

- [ ] Reused or hot-path regular expressions should be precompiled.
- [ ] Template files should access object properties according to the template engine convention, not by duplicating getter logic.
- [ ] Template variables should use the project-safe null-handling form so null or missing values are not rendered unexpectedly.
- [ ] Use `Random.nextInt`, `ThreadLocalRandom`, or equivalent APIs for random integers; do not derive integers from `Math.random` casually.
- [ ] Use `System.currentTimeMillis` for wall-clock timestamps.
- [ ] Use `System.nanoTime` for elapsed time.
- [ ] Use Java 8+ time APIs for semantic time when available.

## Recommended / Reference

- [ ] Template files should not contain complex business decisions.
- [ ] Pre-size data structures when growth is predictable.
- [ ] Remove confirmed dead code, obsolete configuration, disabled jobs, unused topics, and obsolete SQL.
- [ ] Temporarily disabled code must have an owner, reason, and restoration condition; otherwise remove it.
