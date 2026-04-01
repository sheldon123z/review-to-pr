# review-to-pr

Claude Code plugin that automates the pipeline from code review findings to Pull Requests.

```
Code Review → GitHub Issue → Worktree Fix → PR → Merge Strategy
```

## Features

- **Review → Issue**: Automatically create tracked GitHub Issues from review findings
- **Worktree Isolation**: Fix code in isolated git worktrees — never touches your working directory
- **Agent-Driven Fixes**: Leverages AI agents (codex, claude, gemini, etc.) to auto-fix findings
- **Severity-Based Merge**: Low severity auto-merges after CI; medium/high waits for human review
- **Loop Prevention**: Three-layer protection prevents reviewing auto-generated fix commits
- **Lazy Cleanup**: Worktrees are cleaned up when their PRs are merged/closed

## Install

```bash
claude plugin add /path/to/review-to-pr
```

## Quick Start

```bash
# Initialize in your project
/review-to-pr-init

# Fix a single review finding
/review-fix roborev 20

# Fix all open findings
/review-fix-all

# Check status
/review-status

# Clean up completed worktrees
/review-cleanup
```

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| Claude Code | Yes | Plugin host |
| git | Yes | Worktree and branch management |
| gh CLI | Yes | GitHub Issue/PR creation and merge |
| roborev | Optional | Default review source |
| python3 | Yes | State file management |

## Configuration

After running `/review-to-pr-init`, a `review-to-pr.toml` is created in your project root:

```toml
[review]
agent = "codex"              # Default review/fix agent
model = ""                   # Agent model (empty = default)
backup_agent = "claude"      # Fallback agent
backup_model = ""

[merge]
auto_merge_severity = ["low"]
ci_timeout_seconds = 300
merge_method = "squash"

[templates]
language = "zh"              # zh / en
```

## Supported Review Sources

| Source | Command | Status |
|--------|---------|--------|
| roborev | `/review-fix roborev <job-id>` | Fully supported |
| inline | `/review-fix inline` | Paste review content |

## License

MIT
