---
name: worktree-cleanup
description: Clean up git worktrees created for PR reviews.
---

# Worktree Cleanup

Remove git worktrees that were created for PR reviews, especially those where the PR has been merged or closed.

## Usage

Invoke with: `/worktree-cleanup`

## Execution Steps

When this command is invoked:

1. **List all worktrees**:
   ```bash
   git worktree list --porcelain
   ```

2. **Identify PR worktrees**:
   - Filter worktrees matching the pattern `*-pr-<number>`
   - Extract the PR number from the directory name

3. **Check PR status for each**:
   - Use `gh pr view <pr-number> --json state,mergedAt,closedAt` to get status (add `--repo <owner>/<repo>` if the PR belongs to a different repository than the current directory)
   - Categorize as:
     - **Merged**: PR was merged (safe to remove)
     - **Closed**: PR was closed without merge (safe to remove)
     - **Open**: PR is still open (warn before removing)

4. **Present findings**:
   ```
   Found 3 PR worktrees:

   MERGED (safe to remove):
     ../AIchemist-pr-42  →  PR #42: Add feature X (merged 2 days ago)
     ../AIchemist-pr-38  →  PR #38: Fix bug Y (merged 1 week ago)

   OPEN (still active):
     ../AIchemist-pr-45  →  PR #45: Update docs (opened 1 hour ago)

   Remove merged/closed worktrees? [y/N]
   ```

5. **Remove worktrees** (on confirmation):
   ```bash
   git worktree remove <path> --force
   ```

   - Use `--force` if there are untracked files (after warning user)
   - Also clean up the local branch if it exists (and the PR is known to be merged/closed):
     ```bash
     if git show-ref --verify --quiet "refs/heads/<branch-name>"; then
       git branch -d <branch-name> || git branch -D <branch-name>
     fi
     ```

6. **Prune stale worktree references**:
   ```bash
   git worktree prune
   ```

7. **Summary**:
   ```
   ✓ Removed 2 worktrees
   ✓ Pruned stale references

   Remaining worktrees:
     ../AIchemist-pr-45 (PR #45 - still open)
   ```

## Options

The user can specify behavior inline:

- `/worktree-cleanup` — Interactive mode (default), asks before removing
- `/worktree-cleanup --merged` — Only remove worktrees for merged PRs
- `/worktree-cleanup --all` — Remove all PR worktrees (asks for confirmation)

## Error Handling

- If no PR worktrees found, inform user: "No PR worktrees found to clean up"
- If a worktree has uncommitted changes, warn and skip by default; only proceed with forced removal after explicit user confirmation
- If `gh` CLI fails, fall back to just listing worktrees without PR status
- If worktree removal fails, show error and continue with others

## Notes

- Only removes worktrees matching the `*-pr-*` naming pattern
- Does not touch worktrees created for other purposes
- Pairs with `/worktree-pr` command for the full workflow
