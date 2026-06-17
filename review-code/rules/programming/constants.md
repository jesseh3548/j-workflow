# Programming Specification: Constant Conventions

## Mandatory

- [ ] Constant names use uppercase words separated by underscores.
- [ ] Constant names must carry complete business meaning. Avoid vague names such as `MAX_COUNT` when the bounded thing is not clear.
- [ ] Magic values are not allowed in business code unless they are obvious language/library constants.
- [ ] Long literals use uppercase `L`, not lowercase `l`.

## Recommended

- [ ] Split constants by purpose: cache keys, configuration keys, error codes, topics, statuses, limits, and domain-specific constants.
- [ ] Shared constants should live at the narrowest practical scope.
- [ ] Cross-application constants belong in client/shared modules.
- [ ] Application-wide constants belong in shared/common modules.
- [ ] Package-only constants belong in the current package.
- [ ] Class-only constants should be `private static final` inside that class.
- [ ] Use enums for values that have a fixed range or carry attributes.
- [ ] Do not define the same logical value independently in multiple classes; divergence can cause production-only bugs.

## Review Hotspots

- [ ] String status values repeated in multiple files.
- [ ] Error code literals embedded in control flow.
- [ ] Cache key fragments composed inline.
- [ ] Configuration keys typed manually at call sites.
- [ ] Limits such as page size, retry count, timeout, and batch size without named constants.
