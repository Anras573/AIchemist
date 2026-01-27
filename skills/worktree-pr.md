---
name: worktree-pr
description: Create a git worktree for a PR and launch a code review agent in a new terminal.
arguments:
  - name: pr
    description: The PR number to review
    required: true
---

# Worktree PR Review

Create an isolated git worktree for reviewing a pull request, then launch a new Claude Code session with the code review agent.

## Usage

Invoke with: `/worktree-pr <pr-number>`

Examples:
- `/worktree-pr 42`
- `/worktree-pr 123`

## Execution Steps

When this command is invoked:

1. **Validate PR exists**: Use `gh pr view <pr-number> --json number,headRefName,title,state` to:
   - Confirm the PR exists
   - Get the branch name (`headRefName`)
   - Get the PR title for display
   - Verify the PR is open (warn if closed/merged but continue if user confirms)

2. **Determine worktree path**:
   - Get the current repository name from the directory
   - Create sibling directory path: `../<repo-name>-pr-<pr-number>`
   - Example: `../my-repo-pr-42`

3. **Check for existing worktree**:
   - Run `git worktree list` to check if a worktree already exists at that path
   - If exists, ask user: "Worktree already exists. Remove and recreate, or use existing?"

4. **Fetch and create worktree**:
   ```bash
   # Fetch the PR branch into a local branch
   git fetch origin pull/<pr-number>/head:<branch-name>

   # Create the worktree from the fetched branch
   git worktree add <worktree-path> <branch-name>
5. **Launch review session**:
   - Detect the user's terminal/OS:
     - **macOS**: Use AppleScript via `osascript`, for example: `osascript -e 'tell application "Terminal" to do script "cd <worktree-path> && claude \"/review-pr\""'`, or check for iTerm2, Warp, etc.
     - **Linux**: Use one of:
       - `gnome-terminal -- bash -c "cd <worktree-path> && claude '/review-pr'"`
       - `konsole --workdir <worktree-path> -e bash -c "claude '/review-pr'"`
       - `xterm -e bash -c "cd <worktree-path> && claude '/review-pr'"`
     - **Windows**:
       - Windows Terminal (Command Prompt): `wt.exe -d <worktree-path> cmd /k "claude /review-pr"`
       - Windows Terminal (PowerShell): `wt.exe -d <worktree-path> pwsh -c "claude /review-pr"`
       - Classic Command Prompt: `cmd.exe /k "cd /d <worktree-path> && claude /review-pr"`
     - **WSL**: From within a WSL shell, you can run the same command as on Linux (see below).

   - On macOS/Linux/WSL, open a new terminal window and execute:
     ```bash
     cd <worktree-path> && claude "/review-pr"
     ```

   - If terminal detection fails, output manual instructions:
     ```
     Worktree created at: ../<repo-name>-pr-<pr-number>

     To start the review, run in a new terminal:
       cd <worktree-path> && claude "/review-pr"
     ```

6. **Confirm to user**:
   ```
   ✓ Created worktree for PR #<number>: <title>
   ✓ Location: <worktree-path>
   ✓ Launched code review in new terminal

   When finished, clean up with: /worktree-cleanup
   ```

## Error Handling

- If PR number is not provided, ask the user for it
- If PR doesn't exist, show error with suggestion to check the number
- If branch already checked out in another worktree, offer to remove it first
- If `gh` CLI is not authenticated, prompt user to run `gh auth login`
- If worktree creation fails, show the git error and suggest manual steps

## Dependencies

- `gh` CLI (GitHub CLI) must be installed and authenticated
- `git` with worktree support (Git 2.5+)
- `claude` CLI must be available in PATH

## Notes

- The worktree is created as a sibling directory to avoid IDE confusion
- The review runs in a separate terminal so you can continue working
- Use `/worktree-cleanup` to remove worktrees after reviews are complete
