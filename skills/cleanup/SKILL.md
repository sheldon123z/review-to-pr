---
name: review-cleanup
description: "Clean up worktrees and branches from completed review-to-pr fixes. Use when user says 'clean up worktrees', 'review cleanup', 'remove fix branches', or '/review-cleanup'."
argument-hint: "[--all]"
allowed-tools: ["Bash", "Read"]
---

# Clean Up Review-to-PR Worktrees

Remove worktrees and branches that are no longer needed.

## Usage

```
/review-cleanup            # Clean only merged/closed PR worktrees
/review-cleanup --all      # Force clean ALL worktrees (including open PRs)
```

## Process

### Default Mode (no --all)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/autofix.sh" --cleanup
```

Only cleans worktrees whose PRs have been merged or closed. Safe to run anytime.

### Force Mode (--all)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/autofix.sh" --cleanup-all
```

**Warning**: This removes ALL worktrees including those with open PRs. The remote branches and PRs remain — only local worktrees are removed. Ask user for confirmation before running with `--all`.

### Report

After cleanup, show what was removed and what remains.
