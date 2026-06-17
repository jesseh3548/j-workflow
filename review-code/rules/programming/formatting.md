# Programming Specification: Formatting Style

Formatting issues usually should not block unless they hide logic, break project automation, or create maintenance risk.

## Mandatory

- [ ] Empty blocks may be `{}` on one line. Non-empty blocks keep the opening brace on the same line and put content on following lines.
- [ ] A closing brace starts its own line. Do not add an extra line break after it when followed by `else` or a comma.
- [ ] Do not put spaces immediately after `(` or immediately before `)`.
- [ ] Put one space between control keywords such as `if`, `for`, `while`, `switch` and the opening parenthesis.
- [ ] Put one space around assignment, logical, arithmetic, and ternary operators.
- [ ] Use 4 spaces for indentation; do not use tabs.
- [ ] Keep Java lines within 120 columns except imports.
- [ ] When wrapping long expressions, indent continuation lines and move `.` or operators to the next line with the following expression.
- [ ] Put one space after commas in method declarations and calls.
- [ ] Use UTF-8 and Unix LF line endings.

## Recommended

- [ ] Do not align variable declarations with extra spaces; it creates noisy diffs.
- [ ] Use a single blank line between logical sections, not multiple blank lines.
- [ ] Wrap long fluent calls or builders at semantic boundaries.
- [ ] Review formatter/checkstyle/spotless configuration before reporting style issues.
