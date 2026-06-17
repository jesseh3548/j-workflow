# Programming Specification: OOP Rules

## Mandatory

- [ ] Static fields and methods are accessed through the class name, not through an instance.
- [ ] Overridden methods must use `@Override`.
- [ ] Varargs appear last and should not be used as a loosely typed `Object...` bucket.
- [ ] Do not change published interface signatures casually.
- [ ] Deprecated APIs need `@Deprecated` and a migration note.
- [ ] Do not introduce new usage of deprecated classes or methods unless there is a documented compatibility reason.
- [ ] Call `equals` from constants or definitely non-null objects, or use `Objects.equals`.
- [ ] Compare wrapper classes with `equals`, not `==`.
- [ ] Do not compare floating-point values with direct equality; use tolerance or `BigDecimal` according to business semantics.
- [ ] POJO fields use wrapper types.
- [ ] RPC method parameters and return values should use wrapper types so missing/failed/unknown values can be represented.
- [ ] POJO fields should not have default values that mask missing database or RPC data.
- [ ] Do not change `serialVersionUID` for compatible serialized class additions; change it only for deliberately incompatible serialization changes.
- [ ] Constructors must not contain business logic.
- [ ] POJOs should implement `toString`; subclasses include `super.toString()` when useful for troubleshooting.

## Null Handling

- [ ] Strings should normally use `StringUtils.isBlank/isNotBlank` or the project equivalent instead of raw null-only checks.
- [ ] Collections and maps should use `CollectionUtils`/`MapUtils` or project equivalents when available.
- [ ] General object null checks may use `Objects.isNull/nonNull` or direct comparisons when clearer.
- [ ] Guard intermediate objects before chained access.
- [ ] Check wrapper values before unboxing, especially database results, RPC results, map lookups, and configuration reads.

## Recommended / Reference

- [ ] Check `String.split` results before indexed access, especially when input may end with separators.
- [ ] Keep overloaded methods together.
- [ ] Order methods roughly as public/protected entry points, private helpers, then accessors.
- [ ] Setter parameters match field names, and getters/setters should not contain business logic.
- [ ] Use `StringBuilder` for heavy string concatenation inside loops.
- [ ] Use `final` when it clarifies non-reassignment or inheritance constraints.
- [ ] Treat `clone()` as shallow copy by default; implement explicit deep copy when needed.
- [ ] Keep visibility as narrow as possible.
- [ ] Utility classes should not expose public/default constructors.
