# Minimal API Endpoints

No MVC controllers. Each HTTP operation is its own static class with a single `Handle` method, using ASP.NET Core's minimal API parameter-binding to inject route values, the authenticated user, services, and a `CancellationToken`.

## Endpoint handler

- Class name: `<Verb><Feature>Endpoint` (`GetUpcomingSessionsEndpoint`, `SessionSignUpEndpoint`, `SessionRemovePlayerEndpoint`).
- One `public static async Task<IResult> Handle(...)` method — parameters are resolved by the minimal API binder, not passed manually. Order: route/query parameters, `ClaimsPrincipal`/framework types, injected services, `CancellationToken` last.
- Response/request DTOs are `public record` types declared **in the same file**, below the handler class — not in a shared `Dtos/` folder.
- Comment each non-obvious step (auth lookup, spec construction, save) with a short `//` line — these handlers read like a script.

```csharp
using DnDSessionPlanner.Server.Infrastructure.Repositories;
using DnDSessionPlanner.Server.Sessions.Specifications;

namespace DnDSessionPlanner.Server.Sessions;

public sealed class GetUpcomingSessionsEndpoint
{
    public static async Task<IResult> Handle(
        IRepository<Session> sessionRepository,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        var today = DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime);
        var endDate = today.AddMonths(3);

        var spec = new SessionsByDateRangeSpecification(today, endDate, includePlayers: true);
        var sessions = await sessionRepository.ListAsync(spec, cancellationToken);

        var response = sessions
            .OrderBy(s => s.Date)
            .Select(s => new SessionDto(
                s.Id.Value,
                s.Date,
                [.. s.Players.Select(p => new PlayerDto(p.Id.Value, p.Name))]))
            .ToList();

        return Results.Ok(response);
    }
}

public record SessionDto(Guid Id, DateOnly Date, List<PlayerDto> Players);
public record PlayerDto(Guid UserId, string Name);
```

Endpoints that need the current user read it off `ClaimsPrincipal` via `ClaimTypes.NameIdentifier`, then look it up with `UserManager<User>` — never trust a user ID passed in the request body:

```csharp
var userIdClaim = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
if (userIdClaim is null || !Guid.TryParse(userIdClaim, out var userId))
    return Results.Unauthorized();
```

## Route registration

One static `<Feature>Endpoints` class per feature, with a `Map<Feature>Endpoints(this IEndpointRouteBuilder)` extension method. Route templates are `private const string` fields (never inline string literals repeated across the file).

```csharp
namespace DnDSessionPlanner.Server.Sessions;

public static class SessionEndpoints
{
    private const string SignUpEndpoint = "/sessions/{sessionId}/signup";
    private const string RemovePlayerEndpoint = "/sessions/{sessionId}/remove";
    private const string GetSessionsEndpoint = "/sessions";

    public static IEndpointRouteBuilder MapSessionEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(GetSessionsEndpoint, GetUpcomingSessionsEndpoint.Handle)
            .WithName("GetUpcomingSessions")
            .WithTags("Sessions")
            .WithDescription("Get upcoming D&D sessions for the next 3 months")
            .RequireAuthorization()
            .RequireRateLimiting("sessions")
            .Produces<List<SessionDto>>(StatusCodes.Status200OK)
            .Produces(StatusCodes.Status401Unauthorized);

        // ...remaining endpoints follow the same chain shape

        return endpoints;
    }
}
```

Every mapped endpoint gets the full chain: `.WithName()`, `.WithTags("<Feature>")`, `.WithDescription()`, `.RequireAuthorization()` (unless intentionally anonymous), rate limiting where relevant, and `.Produces<T>(status)` for every status code the handler can return.

## Background work

Long-running or scheduled work (a nightly job, a polling loop) is a `BackgroundService`, not a hosted cron hack. Guard against overlapping runs with a `SemaphoreSlim`, and swallow/log exceptions inside the loop so one bad run doesn't kill the service:

```csharp
public class SessionCreationService(
    IServiceProvider serviceProvider,
    ILogger<SessionCreationService> logger,
    TimeProvider timeProvider) : BackgroundService
{
    private readonly SemaphoreSlim _semaphore = new(1, 1);

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        if (!await _semaphore.WaitAsync(0, cancellationToken))
        {
            logger.LogWarning("Task is already running, skipping this execution");
            return;
        }

        try
        {
            using var scope = serviceProvider.CreateScope();
            // ... resolve scoped services and do the work
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error occurred while running task");
        }
        finally
        {
            _semaphore.Release();
        }
    }
}
```
