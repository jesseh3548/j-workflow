# 命名与编码规范

**基本命名规则**
- [ ] 名称不能以下划线 `_` 或美元符 `$` 开头或结尾
- [ ] 禁止中文、拼音、拼音英文混合命名（国际通用名如 alibaba/taobao/hangzhou 除外）
- [ ] 类名使用 UpperCamelCase（DO/BO/DTO/VO 等领域模型例外）
- [ ] 方法名、参数名、成员变量名、局部变量名使用 lowerCamelCase
- [ ] 常量名使用全大写下划线分隔，语义完整（如 `MAX_STOCK_COUNT` 而非 `MAX_COUNT`）
- [ ] 抽象类以 Abstract 或 Base 开头，异常类以 Exception 结尾，测试类以被测类名开头 + Test 结尾
- [ ] 数组类型定义：`String[] args`，而非 `String args[]`
- [ ] Boolean 变量**不要**用 `is` 前缀（如用 `boolean isSuccess` 会导致部分 RPC 框架序列化错误，getter 方法推导出属性名 `success` 与字段名不匹配）
- [ ] 包名全小写，每个点号后只有一个英文单词，包名用单数
- [ ] 避免不常见的缩写（`AbsClass` → `AbstractClass`，`condi` → `Condition`）

**接口与实现**
- [ ] Service 和 DAO 类必须是接口，实现类以 Impl 结尾
- [ ] 接口方法不要加 public 等修饰符，保持简洁
- [ ] 能力型接口用形容词命名（如 `Translatable`）
- [ ] 枚举类以 Enum 结尾，成员全大写下划线分隔
- [ ] 如果使用了设计模式，建议在类名中体现（如 `OrderFactory`、`LoginProxy`、`ResourceObserver`）

**Service/DAO 方法命名约定**
- [ ] 获取单个对象 → `get` 前缀；获取多个 → `list` 前缀；统计 → `count` 前缀
- [ ] 保存 → `insert` 或 `save`；删除 → `delete` 或 `remove`；更新 → `update`

**领域模型命名**
- [ ] DO 对应表名，DTO 对应领域名，VO 对应页面名，不使用 *POJO 命名

**常量使用**
- [ ] 禁止魔法值（`"Id#taobao_" + tradeId` 这种硬编码字符串）
- [ ] long 类型用 `L` 而非 `l`（`2l` 容易与 `21` 混淆）
- [ ] 常量按功能拆分到不同常量类（如 `CacheConsts`、`ConfigConsts`）
- [ ] 跨应用共享常量放 client.jar 的 constant 目录；应用内共享放 shared 模块；子工程/包/类内的常量逐级收窄范围
- [ ] 固定范围值或带属性的值使用枚举
