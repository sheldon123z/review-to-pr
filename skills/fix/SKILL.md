---
name: review-fix
description: "Process a code review finding into a GitHub Issue, isolated worktree fix, and Pull Request. Use when user says 'review fix', 'fix review', 'process review finding', 'create fix PR from review', or '/review-fix'."
argument-hint: "[source] [job-id]"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Agent"]
---

# Fix a Code Review Finding

Convert a single review finding into a tracked, isolated fix with full GitHub integration.

## Usage

```
/review-fix                     # Interactive: ask for source and job ID
/review-fix roborev 20          # Fix roborev job #20
/review-fix inline              # Paste review content inline
```

## Process

### 1. Determine Source & Job ID

If arguments provided, use them. Otherwise ask the user:
- **roborev**: Run `roborev fix --list` to show available jobs, ask user to pick one
- **inline**: Ask user to paste the review content

### 2. Execute Autofix Pipeline

For roborev source, run the autofix script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/autofix.sh" --source roborev --job-id <JOB_ID>
```

For inline source:
1. Save the review content to a temp file
2. Run: `bash "${CLAUDE_PLUGIN_ROOT}/lib/autofix.sh" --source inline --review-file /tmp/review-input.md`
3. If the script creates a worktree but doesn't auto-fix (non-roborev source), spawn the **fixer** agent in the worktree to perform the fix

### 3. Post-Fix Actions

After the script completes:
- If PR was created: show the PR URL
- If auto-merged (low severity): confirm success
- If waiting for review (medium/high): remind user to review the PR
- If no changes: report that the fix produced no code changes

### 4. Spawn Fixer Agent (if needed)

For non-roborev sources where automated fix isn't available, spawn the fixer agent:

```
Agent(subagent_type="review-to-pr:fixer", prompt="Fix the code issues described in .review-report.md in the current worktree at /tmp/review-fix-<id>")
```

The fixer agent will:
1. Read the review report
2. Analyze the codebase
3. Apply fixes
4. The autofix script handles commit/push/PR after agent completes

## Error Handling

- If roborev is not installed and source=roborev: suggest `/review-to-pr-init` first
- If gh CLI is not authenticated: prompt `! gh auth login`
- If worktree creation fails: check for residual worktrees with `/review-status`
- If CI fails: report failure, PR remains open for manual review
