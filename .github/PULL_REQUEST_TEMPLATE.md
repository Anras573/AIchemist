## Description

<!-- What does this PR do? Why is it needed? -->

## Type of Change

<!-- Check the relevant option -->

- [ ] `feat` - New feature
- [ ] `fix` - Bug fix
- [ ] `docs` - Documentation update
- [ ] `refactor` - Code refactoring
- [ ] `chore` - Maintenance (CI, dependencies, etc.)
- [ ] Other: <!-- specify -->

## Breaking Change?

- [ ] Yes (title should include `!` after type, e.g., `feat!:`)
- [ ] No

## Checklist

- [ ] PR title follows [Conventional Commits](https://www.conventionalcommits.org/) format
- [ ] Commit messages follow Conventional Commits format
- [ ] Documentation updated (if applicable)
- [ ] New placeholders documented in README (if any added)

### Tools (`tools/`) — if this PR touches a shell tool

- [ ] Script tested end-to-end locally (not just read)
- [ ] Companion `skills/<name>/SKILL.md` updated in this PR (new commands, flags, dependencies)
- [ ] All fields referenced in SKILL.md workflows are included in API `$select` queries
- [ ] Shell snippets in SKILL.md docs tested in a terminal (quote nesting, `$()` substitutions)
- [ ] Python subprocesses use `stdout=subprocess.PIPE, stderr=subprocess.PIPE` (not `capture_output=True`)
- [ ] Shell variables read via `os.environ` in Python heredocs are `export`ed

## Testing

<!-- How can reviewers test this change? -->

## Related Issues

<!-- Link any related issues: Fixes #123, Closes #456 -->
