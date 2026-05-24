# 流程控制

- [ ] switch 每个 case 必须以 `break`/`return` 结束，未结束需加注释说明；每个 switch 块必须有 `default`（即使为空）
- [ ] `if`/`else`/`for`/`do`/`while` 必须加大括号，禁止 `if (condition) statement;` 单行写法
- [ ] 避免过多 else，用卫语句（guard clause）提前 return；if-else 嵌套不超过 3 层
- [ ] 复杂条件表达式提取为有意义的 boolean 变量，提高可读性
- [ ] 对象和变量声明、数据库连接、try-catch 尽量放在循环外
- [ ] 批量操作必须校验入参大小
- [ ] 以下场景必须校验入参：低频方法、长耗时方法、高稳定性方法、对外 API（RPC/HTTP）、权限相关方法
- [ ] 以下场景可不校验：高频循环内部（外部校验）、DAO 层与 Service 同机部署时、私有方法且调用方已校验
