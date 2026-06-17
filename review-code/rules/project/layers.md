# Project Specification: Application Layers

## Layer Responsibilities

- [ ] Open Interface exposes RPC/HTTP contracts and handles gateway-level security or flow control.
- [ ] Web layer handles routing, access control, and basic parameter validation.
- [ ] Web layer should not accumulate reusable business logic.
- [ ] Service layer owns concrete business logic and transaction boundaries.
- [ ] Manager layer wraps third-party services, preprocesses responses and exceptions, hosts reusable middleware/cache logic, and composes DAOs.
- [ ] DAO layer owns persistence access.
- [ ] Upper layers depend on lower layers. Lower layers should not call upward into Web/Open Interface.

## Exceptions Across Layers

- [ ] DAO exceptions may be wrapped as DAO-specific exceptions without logging if upper layers log consistently.
- [ ] Service/Manager exception logs must include enough parameter and business context.
- [ ] Web layer should convert failures into user/API responses instead of leaking raw exceptions.
- [ ] Open Interface should return structured error code and message contracts.

## Domain Model Boundaries

- [ ] `DO` maps to table structure and flows upward from DAO.
- [ ] `DTO` crosses Service/Manager boundaries.
- [ ] `BO` carries business semantics and may be output by Service.
- [ ] `Query` carries search conditions.
- [ ] Avoid `Map` when there are more than two query conditions.
- [ ] `VO` is for display/API view models.
- [ ] Do not leak persistence DOs directly to external API responses unless this is an established project pattern.
