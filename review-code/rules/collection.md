# 集合使用

- [ ] 重写 `equals` 必须同时重写 `hashCode`；Set 元素和 Map 的 key 必须重写这两个方法
- [ ] 不要向 `keySet()`/`values()`/`entrySet()` 返回的集合添加元素
- [ ] 不要向 `Collections.emptyList()`/`singletonList()` 等不可变集合添加/删除元素
- [ ] `ArrayList.subList` 返回的是内部类视图，不要强转为 `ArrayList`；修改原 list 大小后操作 subList 可能抛 `ConcurrentModificationException`
- [ ] `list.toArray(T[])` 传入与 list 大小一致的数组（`new String[list.size()]`），不用无参 `toArray()`（返回 `Object[]` 无法强转）
- [ ] `Arrays.asList` 转换后不要使用 `add`/`remove`/`clear`（底层仍是数组）
- [ ] 泛型通配符：`<? extends T>` 不能 add，`<? super T>` 不能 get（PECS 原则）
- [ ] `foreach` 循环中禁止添加/删除元素，必须用 `Iterator` 操作；并发场景下对 Iterator 加锁
- [ ] `Comparator` 必须满足自反性、传递性、对称性，否则 `Arrays.sort` 抛 `IllegalArgumentException`
- [ ] 初始化集合时指定大小（`new ArrayList<>(expectedSize)`）
- [ ] 遍历 Map 用 `entrySet` 而非 `keySet`（后者遍历两次），JDK8+ 用 `Map.forEach`
- [ ] 注意各集合对 null 的支持：`ConcurrentHashMap`/`Hashtable`/`TreeMap` 的 key 不允许 null，`ConcurrentHashMap`/`Hashtable` 的 value 不允许 null
- [ ] 去重用 `Set`，不要用 `List.contains()` 遍历比较
