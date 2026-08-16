# Testing Conventions

Two test projects: `<Project>.Tests` for fast unit tests against domain/pure logic, `<Project>.IntegrationTests` for full-stack HTTP tests through a `WebApplicationFactory`.

## Framework

- **xunit** + **Moq**. No FluentAssertions — plain `Assert.*`.
- Test `.csproj` adds `<Using Include="Xunit" />` as a global using, so individual files don't need `using Xunit;`.
- Same `Nullable=enable` / `ImplicitUsings=enable` as the main project, plus `IsPackable=false`.

## Unit tests

- One `[Fact]` per behavior (no `[Theory]` unless the cases genuinely share one assertion shape).
- Naming: `MethodName_Scenario_ExpectedResult` (`SignUp_WithDuplicateUser_ReturnsFalse`, `RemovePlayer_WithNullUser_ThrowsArgumentNullException`).
- Every test body has `// Arrange` / `// Act` / `// Assert` comment sections, even for one-liners.
- Assert on outcomes and observable state (`Assert.True`, `Assert.Single`, `Assert.Contains`, `Assert.Empty`, `Assert.Throws<T>`), not on internal implementation details.

```csharp
using DnDSessionPlanner.Server.Sessions;
using DnDSessionPlanner.Server.Users;

namespace DnDSessionPlanner.Server.Tests;

public class SessionTests
{
    [Fact]
    public void SignUp_WithNewUser_ReturnsTrue()
    {
        // Arrange
        var session = Session.Create(new DateOnly(2026, 1, 15));
        var user = User.Create("John Doe", "john@example.com");

        // Act
        var result = session.SignUp(user);

        // Assert
        Assert.True(result);
        Assert.Single(session.Players);
        Assert.Contains(user, session.Players);
    }

    [Fact]
    public void SignUp_WithNullUser_ThrowsArgumentNullException()
    {
        // Arrange
        var session = Session.Create(new DateOnly(2026, 1, 15));

        // Act & Assert
        Assert.Throws<ArgumentNullException>(() => session.SignUp(null!));
    }
}
```

Cover, for every public mutator: the happy path, the "already in that state" no-op path, and the null-argument guard.

## Integration tests

- One test class per endpoint: `<Endpoint>Tests` (`SessionSignUpEndpointTests`).
- Shared `CustomWebApplicationFactory` (swaps in a test database/config) and a `ClientFactory` helper that hands back an authenticated `HttpClient` so individual tests don't repeat login boilerplate.
- A `TestDataSeeder` populates known fixtures rather than each test hand-rolling entities inline.

## Mocking

Use Moq for interfaces/services under unit test (`Mock<IRepository<Session>>`, `Mock<IEmailSender>`), not for the entities themselves — entities are constructed directly via their `Create` factory since they have no external dependencies.
