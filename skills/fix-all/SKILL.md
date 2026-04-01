---
name: review-fix-all
description: "Process all open code review findings at once. Use when user says 'fix all reviews', 'process all findings', 'review fix all', or '/review-fix-all'."
argument-hint: "[--dry-run]"
allowed-tools: ["Bash", "Read"]
---

# Fix All Open Review Findings

Batch process all open code review findings through the Issue → Worktree → PR pipeline.

## Usage

```
/review-fix-all                 # Process all open findings
/review-fix-all --dry-run       # Preview without executing
```

## Process

### 1. List Open Findings

Run the autofix script in list mode first to preview:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/autofix.sh" --source roborev --all --dry-run
```

Show the user what will be processed and ask for confirmation.

### 2. Execute Batch Fix

After confirmation:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/autofix.sh" --source roborev --all
```

### 3. Report Results

After completion, summarize:
- How many findings processed
- How many PRs created
- How many auto-merged (low severity)
- How many awaiting review (medium/high)
- Any failures

Suggest running `/review-status` to see the full picture.
