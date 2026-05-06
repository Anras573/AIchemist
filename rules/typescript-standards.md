---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---

# TypeScript / React Coding Standards

## Coding Standards

- Use TypeScript strict mode; avoid `any` except when truly necessary.
- Prefer `const` over `let`; never use `var`.
- Use meaningful variable and function names.
- Prefer arrow functions for callbacks and inline functions.
- Use async/await for asynchronous operations; avoid raw Promises when possible.
- Prefer named exports over default exports for better refactoring support.
- Use template literals over string concatenation.
- Destructure objects and arrays when it improves readability.

## Type System Best Practices

- Define explicit return types for public functions.
- Use type inference for local variables when types are obvious.
- Prefer interfaces for object shapes; use types for unions and intersections.
- Use discriminated unions for state management and complex types.
- Avoid type assertions (`as`); prefer type guards and narrowing.
- Use `unknown` over `any` when type is truly unknown.
- Leverage `satisfies` operator for type validation without widening.
- Use `const` assertions for literal types.

## Code Design Rules

- DON'T add interfaces/abstractions unless they provide clear value.
- Least-exposure rule: prefer unexported > exported.
- Keep names consistent; pick one style and stick to it.
- Don't edit auto-generated code (`*.generated.ts`, `*.d.ts`).
- Comments explain **why**, not what.
- Don't add unused methods/params.
- When fixing one function, check similar functions for the same issue.
- Reuse existing utilities as much as possible.

## Error Handling

- Use custom error classes for domain-specific errors.
- Prefer early returns for error conditions.
- Never swallow errors silently; always log or rethrow.
- Use Result/Either patterns for expected failures in critical paths.
- Validate inputs at system boundaries.

## React Development

### Component Patterns

- Use functional components exclusively; no class components.
- Prefer composition over inheritance.
- Keep components small and focused (single responsibility).
- Extract custom hooks for reusable logic.
- Use `children` prop for component composition.
- Avoid prop drilling; use context or state management for deep trees.

### Hooks Best Practices

- Follow the Rules of Hooks (top-level only, React functions only).
- Use `useMemo` and `useCallback` sparingly; measure before optimizing.
- Always include all dependencies in dependency arrays.
- Use `useReducer` for complex state logic.
- Prefer `useId` for accessible form controls.
- Clean up effects properly (return cleanup function).

### State Management

- Start with local state; lift up only when necessary.
- Use React Context for "global" state that doesn't change often.
- Consider Zustand, Jotai, or Redux Toolkit for complex state needs.
- Keep state normalized; avoid deeply nested structures.
- Use server state libraries (TanStack Query, SWR) for API data.

### Performance Optimization

- Use React DevTools Profiler to identify bottlenecks.
- Memoize expensive computations with `useMemo`.
- Prevent unnecessary re-renders with `React.memo`.
- Use virtualization (react-virtual, react-window) for long lists.
- Lazy load components with `React.lazy` and Suspense.
- Use `startTransition` for non-urgent state updates.

### Accessibility

- Use semantic HTML elements (`button`, `nav`, `main`, `article`).
- Include ARIA labels where semantic HTML isn't sufficient.
- Ensure keyboard navigation works.
- Maintain focus management for modals and dynamic content.
- Use accessible color contrast ratios.

## Next.js Development

### App Router Patterns

- Use Server Components by default; add `'use client'` only when needed.
- Colocate related files (page, layout, loading, error) in route folders.
- Use Route Groups `(folder)` for organization without affecting URLs.
- Implement proper loading and error boundaries.
- Use `generateMetadata` for SEO.

### Data Fetching

- Fetch data in Server Components when possible.
- Use `fetch` with appropriate caching strategies.
- Implement `revalidatePath` or `revalidateTag` for on-demand revalidation.
- Handle loading states with `loading.tsx`.
- Handle errors with `error.tsx` and `not-found.tsx`.

### Server Actions

- Use Server Actions for form submissions and mutations.
- Validate inputs with Zod or similar.
- Return structured responses for client-side handling.
- Use `useFormStatus` for pending states.
- Implement optimistic updates with `useOptimistic`.

## Node.js Backend

### API Design

- Use Express, Fastify, or tRPC for API endpoints.
- Validate request inputs at the edge.
- Return consistent response shapes.
- Use proper HTTP status codes.
- Implement proper error handling middleware.

### Security

- Sanitize user inputs.
- Use parameterized queries for database access.
- Implement rate limiting for public endpoints.
- Use CORS appropriately.
- Never expose stack traces in production.

### Async Patterns

- Use async/await consistently.
- Handle promise rejections properly.
- Implement timeouts for external calls.
- Use `Promise.allSettled` when failures shouldn't abort other operations.
- Stream large payloads instead of buffering.

## Formatting

Check if a formatter runs in pre-commit hooks (`.git/hooks/pre-commit`, `.husky/`, `lefthook.yml`, `.pre-commit-config.yaml`) before running manually.

1. **Biome** (preferred if present) — if `biome.json` or `@biomejs/biome` in `package.json`: `npx biome format --write .`
2. **Prettier** — if `.prettierrc*` or `"prettier"` in devDependencies: `npx prettier --write .`
3. **ESLint** — for linting and autofix: `npx eslint . --fix`

CI check-only: `npx biome ci .` / `npx prettier --check .` / `npx eslint . --max-warnings 0`

## Testing

### Test Structure

- Separate test files: `*.test.ts` or `*.spec.ts`.
- Mirror source structure in test folders.
- Name tests by behavior: `should render loading state while fetching`.
- Follow Arrange-Act-Assert (AAA) pattern.
- One assertion per test when possible.

### Unit Tests

- Test pure functions and utilities first.
- Mock external dependencies (APIs, databases).
- Test edge cases and error conditions.
- Use factories for test data.

### Component Tests

- Use React Testing Library; query by role or label, not test IDs.
- Test behavior, not implementation details.
- Don't test internal state; test what users see.
- Use `userEvent` over `fireEvent` for realistic interactions.
- Test accessibility with `jest-axe`.

### Integration Tests

- Test complete user flows.
- Use MSW (Mock Service Worker) for API mocking across unit, integration, and component tests.
- Test form submissions and navigation.
- Verify loading and error states.

### E2E Tests

- Use Playwright or Cypress for critical paths.
- Keep E2E tests focused on happy paths.
- Use page object pattern for maintainability.
- Run against production-like environment.

### Mocking

- Use whatever mocking utilities are already in the project.
- For new projects with **Vitest**: prefer native `vi.fn()` / `vi.mock()`.
- For new projects with **Jest**: prefer native `jest.fn()` / `jest.mock()`.
- For HTTP mocking: prefer **MSW** — works across unit, integration, and component tests.
- Avoid heavy mocking libraries (sinon, testdouble) unless already present.

### Coverage

- Aim for meaningful coverage, not 100%.
- Cover critical business logic thoroughly.
- Don't test library code or generated code.

## Ecosystem Versions

| React | Notable features |
|-------|-----------------|
| 18 | Concurrent rendering; `useId`; `useTransition`; `useDeferredValue`; Suspense SSR streaming |
| 19 | Actions (`useActionState`, `useFormStatus`); `use()` hook; `useOptimistic`; Server Components stable; ref as prop (no `forwardRef`) |

| Next.js | Notable features |
|---------|-----------------|
| 13 | `app/` directory (beta); Server Components; layouts; `loading.tsx` / `error.tsx` |
| 14 | App Router stable; Server Actions stable; Partial Prerendering (experimental) |
| 15 | React 19 support; `next/after`; `instrumentation.ts` stable; `fetch` no longer cached by default |

## Quick Checklist

### Initial Check

- Review `tsconfig.json` and `package.json` (compiler settings, deps, scripts).
- Identify framework (React, Next.js, Node.js).
- Check for existing linting/formatting config.

### Before Coding

- Understand the project structure.
- Check for existing patterns and utilities.
- Review relevant documentation.

### After Coding

- TypeScript compiles without errors.
- Tests pass.
- No linting warnings.
- Changes are focused and minimal.
