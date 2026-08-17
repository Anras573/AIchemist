# Style & Formatting

## Project settings

Every `.csproj` (main and test projects) sets:

```xml
<TargetFramework>net10.0</TargetFramework>
<ImplicitUsings>enable</ImplicitUsings>
<Nullable>enable</Nullable>
```

Use the current .NET LTS/STS in place of `net10.0` if a newer one is out. Test projects additionally set `<IsPackable>false</IsPackable>`.

## Language features (from `.editorconfig`)

- **File-scoped namespaces** (`namespace Foo.Bar;`), not block-scoped.
- **Primary constructors** preferred for classes that just capture constructor-injected dependencies (`public class Repository<T>(DbContext context)`).
- **Collection expressions**: `[]` for empty/new collections, `[.. source.Select(...)]` for building a list from a projection.
- **`var`** is *not* preferred by default (`csharp_style_var_*` are all off) — spell out the type unless it's genuinely apparent (e.g. `new(...)`).
- Expression-bodied members: accessors, indexers, properties → yes; constructors, methods, operators, local functions → no (use a block body).
- Pattern matching preferred over `as` + null-check or `is` + cast.
- `using` directives: `System.*` sorted first, one group (not separated by blank lines).
- 4-space indentation, braces on their own line (Allman-style via `csharp_new_line_before_open_brace = all`).

## Naming

| Symbol | Style | Example |
|---|---|---|
| Types, namespaces, methods, properties, events | PascalCase | `SessionCreationService` |
| Interfaces | `I` + PascalCase | `IRepository<T>` |
| Type parameters | `T` + PascalCase | `TEntity` |
| Local variables, parameters | camelCase | `sessionId` |
| Private fields | `_camelCase` | `_players` |
| Private static fields | `s_camelCase` | `s_cache` |
| Constants (public or private) | PascalCase | `SignUpEndpoint` |
| Public static readonly fields | PascalCase | — |

## Copyable `.editorconfig`

[`example.editorconfig`](example.editorconfig) is the full config used in the source project (Rider/`dotnet new editorconfig`-generated, lightly reviewed). Copy it to the root of a new .NET repo as `.editorconfig`.
