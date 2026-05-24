# MySQL / 数据层规范

**表结构**
- [ ] Boolean 字段命名 `is_xxx`，类型 `unsigned tinyint`（1=True, 0=False）；非负值字段用 `unsigned`
- [ ] 表名列名全小写字母+数字+下划线，禁止数字开头，禁止两个下划线间只有数字
- [ ] 表名禁止复数
- [ ] 禁止用 MySQL 关键字做表名列名（`desc`、`range`、`match`、`delayed` 等）
- [ ] 索引命名：主键 `pk_列名`，唯一索引 `uk_列名`，普通索引 `idx_列名`
- [ ] 小数用 `decimal`，禁止 `float`/`double`
- [ ] 固定长度字段用 `char`
- [ ] `varchar` 长度不超过 5000，超过用 `text` 并独立表存储
- [ ] 表必须有 `id`（unsigned bigint 自增）、`gmt_create`（DATETIME）、`gmt_modified`（DATETIME）三个字段
- [ ] 单表超过 500 万行或 2GB 才考虑分表，建表时不要提前分表
- [ ] 列含义变更或新增状态值时及时更新列注释

**索引**
- [ ] 业务上有唯一性约束的字段必须建唯一索引
- [ ] JOIN 不超过 3 张表，JOIN 字段类型必须一致且有索引
- [ ] varchar 建索引必须指定长度（通常 20 即可区分 90%+ 数据）
- [ ] 禁止 `LIKE '%xxx'` 或 `LIKE '%xxx%'`（无法使用 B-Tree 索引左前缀匹配）
- [ ] 组合索引把区分度最高的字段放最左边；等值条件的列优先于范围条件的列
- [ ] ORDER BY 的字段放在组合索引末尾，利用索引排序避免 file_sort
- [ ] 利用覆盖索引避免回表查询（EXPLAIN extra 列出现 Using index）

**SQL**
- [ ] 用 `COUNT(*)` 而非 `COUNT(column)` 或 `COUNT(1)`
- [ ] `COUNT(distinct col1, col2)` 注意：任一列全为 NULL 则返回 0
- [ ] `SUM()` 注意 NULL 返回值（用 `IFNULL(SUM(g), 0)` 或 `IF(ISNULL(SUM(g)), 0, SUM(g))`）
- [ ] 判断 NULL 用 `ISNULL()`，不用 `= NULL`（`NULL = NULL` 返回 NULL 而非 true）
- [ ] 分页查询先判断 count 为 0 则直接返回，不执行后续查询
- [ ] 禁止外键和级联更新，相关逻辑在应用层处理
- [ ] 禁止存储过程
- [ ] 修正/删除数据前必须先 SELECT 确认，确保数据正确
- [ ] IN 子句元素控制在 1000 以内
- [ ] 大分页用延迟 JOIN 或子查询优化（先定位 id 范围再 JOIN）
- [ ] SQL 优化目标：EXPLAIN 达到 REF 级别以上，至少 RANGE，最好 CONSTS

**ORM**
- [ ] 查询必须指定具体列名，禁止 `SELECT *`
- [ ] POJO 的 Boolean 属性不加 is 前缀，但数据库列用 `is_` 前缀，需在 resultMap 中做映射
- [ ] 不要用 `resultClass` 直接返回，必须有 DO 定义和 resultMap 映射（解耦 DO 与表结构）
- [ ] MyBatis XML 中使用 `#{}` 防注入，禁止 `${}`
- [ ] 不要用 `HashMap`/`HashTable` 作为查询结果类型
- [ ] 更新记录时必须同步更新 `gmt_modified`
- [ ] 不要定义万能 update 接口（传入整个 POJO 全量 set），只更新需要改的列
- [ ] 不要滥用 `@Transactional`，评估事务对 QPS 的影响和回滚范围
