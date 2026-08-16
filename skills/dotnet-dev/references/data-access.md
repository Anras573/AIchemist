# Data Access: Repository + Specification

No LINQ scattered across endpoint handlers, and no per-entity repository interfaces. One generic repository, plus a small `Specification<T>` type per distinct query shape.

## Generic repository

`IRepository<T>` / `Repository<T>` wraps the `DbContext`, applies a specification's `Includes` and `Criteria`, and is injected wherever an endpoint needs one:

```csharp
using DnDSessionPlanner.Server.Infrastructure.Specifications;
using Microsoft.EntityFrameworkCore;

namespace DnDSessionPlanner.Server.Infrastructure.Repositories;

public class Repository<T>(DbContext context) : IRepository<T> where T : class
{
    public async Task<T?> FirstOrDefaultAsync(ISpecification<T> specification, CancellationToken cancellationToken = default)
    {
        var query = context.Set<T>().AsQueryable();

        foreach (var include in specification.Includes)
        {
            query = query.Include(include);
        }

        return await query.FirstOrDefaultAsync(specification.Criteria, cancellationToken);
    }

    public async Task<List<T>> ListAsync(ISpecification<T> specification, CancellationToken cancellationToken = default)
    {
        var query = context.Set<T>().AsQueryable();

        foreach (var include in specification.Includes)
        {
            query = query.Include(include);
        }

        return await query.Where(specification.Criteria).ToListAsync(cancellationToken);
    }

    public async Task AddAsync(T entity, CancellationToken cancellationToken = default)
    {
        await context.Set<T>().AddAsync(entity, cancellationToken);
        await context.SaveChangesAsync(cancellationToken);
    }

    public async Task SaveChangesAsync(CancellationToken cancellationToken = default)
        => await context.SaveChangesAsync(cancellationToken);
}
```

Register it once in DI as `services.AddScoped(typeof(IRepository<>), typeof(Repository<>));` — no per-entity `SessionRepository : IRepository<Session>` boilerplate.

## Specification pattern

`Specification<T>` is an abstract base with an abstract `Criteria` expression and a mutable `Includes` list, populated via a protected `AddInclude` helper:

```csharp
using System.Linq.Expressions;

namespace DnDSessionPlanner.Server.Infrastructure.Specifications;

public abstract class Specification<T> : ISpecification<T>
{
    public abstract Expression<Func<T, bool>> Criteria { get; }
    public List<Expression<Func<T, object>>> Includes { get; } = [];

    protected void AddInclude(Expression<Func<T, object>> includeExpression)
    {
        Includes.Add(includeExpression);
    }
}
```

Each distinct query shape gets its own `sealed class` in a `Specifications/` subfolder of the feature, named `<Entity>By<Criteria>Specification`. Filter values are constructor parameters; eager-loading is an opt-in `bool includeX = false` parameter that calls `AddInclude` conditionally:

```csharp
using System.Linq.Expressions;
using DnDSessionPlanner.Server.Infrastructure.Specifications;

namespace DnDSessionPlanner.Server.Sessions.Specifications;

public sealed class SessionByIdSpecification : Specification<Session>
{
    private readonly SessionId _sessionId;

    public SessionByIdSpecification(SessionId sessionId, bool includePlayers = false)
    {
        _sessionId = sessionId;

        if (includePlayers)
        {
            AddInclude(s => s.Players);
        }
    }

    public override Expression<Func<Session, bool>> Criteria => s => s.Id == _sessionId;
}
```

```csharp
public sealed class SessionsByDateRangeSpecification : Specification<Session>
{
    private readonly DateOnly _startDate;
    private readonly DateOnly _endDate;

    public SessionsByDateRangeSpecification(DateOnly startDate, DateOnly endDate, bool includePlayers = false)
    {
        _startDate = startDate;
        _endDate = endDate;

        if (includePlayers)
        {
            AddInclude(s => s.Players);
        }
    }

    public override Expression<Func<Session, bool>> Criteria =>
        s => s.Date >= _startDate && s.Date <= _endDate;
}
```

## When to add a new specification vs. reuse one

Add a new specification class per distinct filter shape. Don't add optional parameters to bend one specification into covering unrelated queries — a `SessionByIdSpecification` and a `SessionsByDateRangeSpecification` are separate types even though both query `Session`.
