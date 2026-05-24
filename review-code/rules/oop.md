# OOP 与代码结构

**基本规则**
- [ ] 静态字段/方法通过类名引用，而非对象实例
- [ ] 重写的方法必须加 `@Override`
- [ ] varargs 参数必须放在参数列表最后，避免使用 `Object` 类型的 varargs
- [ ] 禁止修改已发布接口的方法签名；废弃接口加 `@Deprecated` 并注明新接口
- [ ] 不使用已废弃的类或方法
- [ ] `equals` 由常量或确定非空对象调用（`"test".equals(obj)` 而非 `obj.equals("test")`），或使用 `Objects.equals()`
- [ ] 包装类比较使用 `equals` 而非 `==`（Integer 仅在 -128~127 范围内 `==` 有效）
- [ ] 浮点数比较使用误差范围或 `BigDecimal`，禁止 `==` 和 `equals`

**Null 判断**
- [ ] 避免直接使用 `!= null` / `== null`，优先使用语义化工具方法：
  - String → `StringUtils.isNotBlank()` / `StringUtils.isBlank()`（同时覆盖 null、空串、纯空白）
  - Collection/Map → `CollectionUtils.isNotEmpty()` / `CollectionUtils.isEmpty()`（同时覆盖 null 和空集合）
  - 通用对象 → `Objects.nonNull()` / `Objects.isNull()`，或 `Optional` 链式处理
- [ ] 特别禁止对 String 直接 `== null` 或 `!= null` 后不检查空串（几乎总是应该用 isBlank/isEmpty）

**POJO 规范**
- [ ] POJO 成员必须是包装类（不是基本类型），RPC 方法的参数和返回值必须是包装类
- [ ] POJO 类不要给成员赋默认值
- [ ] 必须实现 `toString()`，继承时先调 `super.toString()`
- [ ] `serialVersionUID` 修改需谨慎：新增字段不改，完全不兼容才改
- [ ] 构造函数中不放业务逻辑，初始化用 `init` 方法

**结构**
- [ ] 方法声明顺序：public/protected → private → getter/setter
- [ ] 同名重载方法放在一起
- [ ] setter 参数名与字段名一致，getter/setter 中不要塞业务逻辑
- [ ] 循环内字符串拼接使用 `StringBuilder.append()`，不用 `+`
- [ ] `String.split()` 后通过索引访问前，检查最后一个分隔符是否为空导致数组长度不符预期
- [ ] 合理使用 `final`：不可继承的类、不可重赋值的变量、不可修改的参数、不可重写的方法
- [ ] 使用 `clone` 要注意是浅拷贝，需深拷贝时自行实现
- [ ] 严格控制访问级别：外部不需要的构造器/字段/方法设为 private，子类需要的设为 protected
