# 工程规范

**应用分层**
- [ ] 是否遵循分层架构：Open Interface → Web → Service → Manager → DAO
- [ ] Web 层只做转发控制和基本参数校验，不放业务逻辑
- [ ] Service 层放具体业务逻辑
- [ ] Manager 层封装第三方服务（预处理返回值和异常）、沉淀通用能力（缓存、中间件）、组合多个 DAO
- [ ] DAO 层异常用 `catch (Exception e)` 包装为 `DAOException` 抛出，不打日志（由上层打）
- [ ] Service/Manager 层异常日志必须携带完整参数信息
- [ ] Web 层不抛异常，渲染失败时跳转友好错误页；Open Interface 用 error code + error message

**领域模型**
- [ ] DO（数据对象）→ DAO 层向上传递
- [ ] DTO（数据传输对象）→ Service/Manager 层向上传递
- [ ] BO（业务对象）→ Service 层输出
- [ ] Query（查询对象）→ 上层传入查询条件，超过 2 个条件禁止用 Map
- [ ] VO（视图对象）→ Web 层展示用

**依赖管理**
- [ ] GAV 命名规范：GroupId `com.{公司}.{业务线}.{子业务线}`；ArtifactId `产品名-模块名`
- [ ] 版本号：主版本号.次版本号.修订号（初始 1.0.0），不可覆盖已发布版本
- [ ] 线上应用禁止依赖 SNAPSHOT 版本
- [ ] 新增/升级依赖时用 `dependency:resolve` 和 `dependency:tree` 对比前后差异，用 `<excludes>` 排除多余依赖
- [ ] 同一 GroupId + ArtifactId 在所有子工程中版本必须一致，版本声明放 `<dependencyManagement>`
- [ ] 类库的接口返回值禁止使用枚举类型（含包含枚举的 POJO）
