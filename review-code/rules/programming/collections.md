# Programming Specification: Collections

## Mandatory

- [ ] If `equals` is overridden, `hashCode` must also be overridden.
- [ ] Objects used as `Set` elements or `Map` keys need stable and consistent `equals/hashCode`.
- [ ] Do not add elements to collection views returned by `keySet`, `values`, or `entrySet`.
- [ ] Do not mutate immutable collections such as `Collections.emptyList` or `singletonList`.
- [ ] `ArrayList.subList` returns a view, not a new `ArrayList`; do not cast it to `ArrayList`.
- [ ] Do not structurally modify the original list after taking a subList that will still be used.
- [ ] Use typed `toArray(T[])`; do not cast the result of raw `toArray()`.
- [ ] Lists returned by `Arrays.asList` have fixed size. Do not call `add`, `remove`, or `clear` on them.
- [ ] Follow PECS for wildcards: `? extends T` is mainly for reading, `? super T` is mainly for writing.
- [ ] Do not add/remove elements in foreach loops; use `Iterator.remove()` when removing during iteration.
- [ ] Concurrent iteration and mutation need synchronization or a proper concurrent collection.
- [ ] Custom `Comparator` implementations must be reflexive, symmetric, and transitive.

## Recommended / Reference

- [ ] Pre-size collections for batch conversions, page results, and aggregation maps.
- [ ] Iterate maps with `entrySet` or `Map.forEach` instead of `keySet` plus `get`.
- [ ] Know which collections allow null keys or values before storing nullable data.
- [ ] Use `Set` or a map keyed by business identity for de-duplication, not repeated `List.contains`.
- [ ] Return immutable empty collections when callers should not mutate.
- [ ] Return fresh mutable collections when mutation is expected.
- [ ] Avoid exposing internal mutable collections directly.
