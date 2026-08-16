# Domain Modeling

## Entities

- `sealed class`, never mutable public setters — properties use `private set` (or are set only inside the class).
- Two constructors: a `private` parameterless one for EF Core materialization, and a `private` "real" one that takes the required fields. A `public static Create(...)` factory is the only public way to construct an instance.
- Collections are encapsulated: a `private readonly List<T>` backing field, exposed publicly as `IReadOnlyCollection<T>` via `.AsReadOnly()`.
- Guard clauses use `ArgumentNullException.ThrowIfNull(...)`, not manual `if (x is null) throw ...`.
- Mutator methods that can no-op on an expected condition (already signed up, not signed up) return `bool` to signal outcome instead of throwing — reserve exceptions for programmer errors (null args), not expected business outcomes.

```csharp
using DnDSessionPlanner.Server.Users;

namespace DnDSessionPlanner.Server.Sessions;

public sealed class Session
{
    private readonly List<User> _players = [];

    public SessionId Id { get; private set; }
    public DateOnly Date { get; private set; }
    public IReadOnlyCollection<User> Players => _players.AsReadOnly();

    // EF Core constructor
    private Session()
    {
        Id = default!;
        Date = default;
    }

    private Session(SessionId id, DateOnly date)
    {
        Id = id;
        Date = date;
    }

    public static Session Create(DateOnly date)
        => new(SessionId.New(), date);

    public bool SignUp(User user)
    {
        ArgumentNullException.ThrowIfNull(user);

        if (_players.Any(p => p.Id == user.Id))
        {
            return false; // User is already signed up
        }

        _players.Add(user);
        return true;
    }

    public bool RemovePlayer(User user)
    {
        ArgumentNullException.ThrowIfNull(user);

        var removedCount = _players.RemoveAll(p => p.Id == user.Id);
        return removedCount > 0;
    }
}
```

## Strongly-typed IDs

Every aggregate root gets a `sealed record <Entity>Id(Guid Value)` instead of a raw `Guid`, to prevent mixing up IDs of different entity types at compile time.

- Static `New()` factory wraps `Guid.NewGuid()`.
- Implicit conversions to/from `string` keep it ergonomic at API boundaries (route parameters, JWT claims) without scattering `.Value.ToString()` / `Guid.Parse(...)` everywhere.
- The EF Core `ValueConverter` for the ID lives in the **same file**, right below the record.

```csharp
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace DnDSessionPlanner.Server.Sessions;

public sealed record SessionId(Guid Value)
{
    public static SessionId New() => new(Guid.NewGuid());

    public static implicit operator string(SessionId id) => id.Value.ToString();
    public static implicit operator SessionId(string id) => new(Guid.Parse(id));
}

/// <summary>
/// EF Core value converter for SessionId to enable database persistence.
/// </summary>
public sealed class SessionIdConverter() : ValueConverter<SessionId, Guid>(
    sessionId => sessionId.Value,
    value => new SessionId(value));
```

Register the converter in the `DbContext`'s `OnModelCreating` via `.HasConversion<SessionIdConverter>()` on the property.

## Naming

- Entity: `<Noun>` (`Session`, `User`).
- Strongly-typed ID: `<Noun>Id`.
- ID's EF value converter: `<Noun>IdConverter`.
