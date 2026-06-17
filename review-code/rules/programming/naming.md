# Programming Specification: Naming Conventions

## Mandatory

- [ ] Names must not start or end with `_` or `$`.
- [ ] Do not use Chinese, Pinyin, or mixed Pinyin-English names, except widely accepted proper nouns such as brands or locations.
- [ ] Class names use UpperCamelCase. Domain suffixes such as `DO`, `BO`, `DTO`, and `VO` remain uppercase.
- [ ] Method names, parameter names, member variables, and local variables use lowerCamelCase.
- [ ] Abstract class names start with `Abstract` or `Base`.
- [ ] Exception class names end with `Exception`.
- [ ] Test class names start with the tested class name and end with `Test`.
- [ ] Array declarations use `String[] args`, not `String args[]`.
- [ ] Boolean fields must not use the `is` prefix, because JavaBean/RPC serializers may infer a different property name.
- [ ] Package names are lowercase. Each package segment should be a single English word when possible.
- [ ] Package names are singular. Utility classes may be plural if that is the project convention.
- [ ] Avoid uncommon abbreviations. Prefer clear domain wording over short names that require decoding.
- [ ] In SOA-style modules, Service and DAO types should be interfaces and implementation classes should end with `Impl`.
- [ ] Interface methods should not include redundant `public` modifiers.
- [ ] Interfaces should not define variables except shared application constants.

## Recommended / Reference

- [ ] If a design pattern is intentionally used, include the pattern role in the class name, such as `Factory`, `Proxy`, or `Observer`.
- [ ] Capability interfaces should be adjective-like, such as `Translatable` or `Retryable`.
- [ ] Enum class names should end with `Enum` unless the project has a stronger existing convention.
- [ ] Service/DAO retrieval methods use `get` for one object, `list` for multiple objects, and `count` for statistics.
- [ ] Data mutation methods use `insert`/`save`, `delete`/`remove`, and `update` consistently.
- [ ] `DO` maps to table structure, `DTO` crosses service/manager boundaries, `BO` carries business semantics, `VO` is presentation/API view data, and `Query` carries query conditions.
- [ ] Do not name a class `*POJO`.
