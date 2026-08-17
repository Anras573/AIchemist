---
name: dotnet-dev
description: |
  Personal C#/.NET conventions to apply when writing, generating, reviewing, or scaffolding .NET code — derived from the user's DnDSessionPlanner project (ASP.NET Core minimal APIs, vertical-slice architecture, EF Core with the specification pattern, xunit + Moq). Trigger on "write this in C#", "write some C#", "add a minimal API endpoint", "add an entity", "add a domain model", "strongly-typed ID", "add a repository", "add a specification", "write xunit tests", "how do I structure a .NET feature", ".editorconfig for a C# project", or any request to write or review ASP.NET Core / EF Core / .NET code.
version: 1.0.0
---

# .NET Development Conventions

Personal C# conventions distilled from [`Anras573/DnDSessionPlanner`](https://github.com/Anras573/DnDSessionPlanner), an ASP.NET Core + EF Core + React (Aspire-hosted) app. Apply these when writing new .NET code or reviewing someone else's, unless the target repo's own `.editorconfig`/`CLAUDE.md` says otherwise — existing repo conventions always win over this skill.

## Architecture

Organize by **feature (vertical slice), not by technical layer**. There is no top-level `Controllers/`, `Services/`, or `Repositories/` folder — each feature folder (e.g. `Sessions/`, `Users/`, `Auth/`) owns its entities, endpoints, and specifications together:

```
Sessions/
  Session.cs                    # entity
  SessionId.cs                  # strongly-typed ID + EF value converter
  SessionEndpoints.cs           # route registration
  GetUpcomingSessionsEndpoint.cs
  SessionSignUpEndpoint.cs
  SessionRemovePlayerEndpoint.cs
  Specifications/
    SessionByIdSpecification.cs
    SessionsByDateRangeSpecification.cs
```

Cross-cutting infrastructure (generic repository, specification base class, email, validation attributes) lives in `Infrastructure/`.

## Quick reference

| Concern | Convention | Details |
|---|---|---|
| Project setup | `net10.0` (or current LTS), `ImplicitUsings=enable`, `Nullable=enable` | [style-and-formatting.md](references/style-and-formatting.md) |
| Formatting/naming | file-scoped namespaces, primary constructors, collection expressions, `_camelCase` private fields | [style-and-formatting.md](references/style-and-formatting.md) |
| Entities & value objects | sealed class, private setters, static `Create()` factory, strongly-typed IDs | [domain-modeling.md](references/domain-modeling.md) |
| HTTP endpoints | one static `Handle` per endpoint, minimal APIs, `Map<Feature>Endpoints` extension | [minimal-api-endpoints.md](references/minimal-api-endpoints.md) |
| Queries & persistence | generic `IRepository<T>` + specification pattern, no raw LINQ in endpoints | [data-access.md](references/data-access.md) |
| Tests | xunit + Moq, AAA comments, `Method_Scenario_Expected` naming | [testing.md](references/testing.md) |

Load the linked reference file for the area you're touching rather than re-deriving the pattern from scratch — each one carries real (trimmed) code from the source project.

## Workflow

1. **New feature** → create a feature folder; add the entity/value object first ([domain-modeling.md](references/domain-modeling.md)), then the endpoint(s) ([minimal-api-endpoints.md](references/minimal-api-endpoints.md)), then a specification if the endpoint needs a non-trivial query ([data-access.md](references/data-access.md)).
2. **New entity** → sealed class, private EF Core constructor, private "real" constructor, public static `Create()` factory, encapsulated collections. Give it a strongly-typed ID if it's an aggregate root.
3. **New endpoint** → static class named `<Verb><Feature>Endpoint` with a single `public static async Task<IResult> Handle(...)` method; register it in `<Feature>Endpoints.MapXEndpoints`; response DTOs are `record`s declared at the bottom of the same file.
4. **New query** → a `Specification<T>` subclass in `Specifications/`, not ad-hoc LINQ scattered across endpoints.
5. **Tests** → one `[Fact]` per behavior in a `MethodName_Scenario_ExpectedResult` shape, `// Arrange` / `// Act` / `// Assert` comments, plain `Assert.*` (no FluentAssertions), Moq for mocks.
6. **New project** → copy [`references/example.editorconfig`](references/example.editorconfig) as the repo's `.editorconfig`.

## When this skill does NOT apply

If the target repo already has its own established conventions (different architecture, a documented style guide, an existing `.editorconfig` with different rules), follow the repo's own conventions instead — this skill encodes one person's preferences for greenfield or unopinionated code, not a mandate to reformat someone else's codebase.
