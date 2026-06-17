# Project Specification: Library Specification

## Mandatory

- [ ] GroupId follows organization/business-line conventions.
- [ ] ArtifactId uses product-module naming.
- [ ] Versioning follows major.minor.patch semantics.
- [ ] Online applications must not depend on SNAPSHOT versions unless an approved security/emergency exception exists.
- [ ] New or upgraded dependencies need impact review using dependency tree/resolve or project equivalents.
- [ ] Related libraries should use a shared version variable to avoid inconsistent versions.
- [ ] The same GroupId and ArtifactId should resolve to one version across submodules.
- [ ] Library API return types should avoid enums when they create compatibility problems for consumers, especially public client libraries.

## Recommended / Reference

- [ ] Declare dependency versions in dependency management and dependencies in module dependency blocks.
- [ ] Libraries should avoid adding configuration unless necessary.
- [ ] Libraries should expose only required APIs and domain models.
- [ ] Avoid dragging unnecessary transitive dependencies.
- [ ] Libraries should depend on logging facades rather than specific logging implementations.
- [ ] Library releases should have traceable changelogs, owners, and source locations.
- [ ] When excluding transitive dependencies, verify runtime still has the required implementation.
