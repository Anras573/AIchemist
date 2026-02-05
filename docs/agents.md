# Agents

Agents are specialized AI assistants invoked via the Task tool. They have focused expertise and can consult each other for cross-domain guidance.

## Code Review Agent

Expert code reviewer with parallel agent support, Jira integration, and confidence scoring.

**Capabilities:**
- Launches parallel review agents (guidelines, bugs, security)
- Triggers file-specific agents (e.g., DDD for domain models, .NET for C# files)
- Confidence scoring (0-100) with threshold filtering to reduce false positives
- Auto-detects Jira tickets from branch name or PR description
- Inline PR comments with committable suggestions

**Invoked by:** `/code-review` command or Task tool

## TypeScript/React Agent

Full-stack TypeScript developer specializing in modern frontend and backend patterns.

**Expertise:**
- React, Next.js, Node.js
- React Hook Form, Zod validation
- Server Components vs Client Components
- State management patterns
- TypeScript type design and narrowing

**Invoked by:** Task tool when working with TypeScript/React code

## .NET Agent

C#/.NET expert covering the full .NET ecosystem.

**Expertise:**
- Async/await patterns and avoiding deadlocks
- SOLID principles
- Domain-Driven Design implementation
- xUnit testing and mocking
- FluentResults and Result patterns
- ASP.NET Core best practices

**Invoked by:** Task tool when working with C#/.NET code, or consulted by Code Review agent

## DDD Agent

Domain-Driven Design expert for strategic modeling and tactical pattern review.

**Expertise:**
- Aggregate design and boundaries
- Entity vs Value Object decisions
- Invariant enforcement
- Bounded context identification
- Domain event patterns

**Language-agnostic:** Provides guidance applicable to any programming language.

**Invoked by:** Task tool for domain modeling questions, or consulted by Code Review agent

## Agent Collaboration

Agents can consult each other for specialized guidance:

- Code Review agent consults .NET agent for C# reviews
- Code Review agent consults TypeScript/React agent for frontend reviews
- Code Review agent consults DDD agent for domain model reviews
