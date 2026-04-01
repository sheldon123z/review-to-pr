---
name: review-to-pr-init
description: "Initialize review-to-pr in the current project. Use when user says 'review-to-pr init', 'setup review automation', 'configure review-to-pr', or wants to set up automated code review → PR pipeline."
argument-hint: "[--force]"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# Initialize review-to-pr

Set up the review-to-pr automation pipeline in the current project. Walk through environment checks, agent selection, and configuration generation.

## Step 1: Environment Detection

Check prerequisites and report status:

```bash
# Check git repo
git rev-parse --show-toplevel 2>/dev/null || echo "NOT_A_GIT_REPO"

# Check gh CLI
gh auth status 2>&1 | head -3

# Check roborev
command -v roborev && roborev version 2>&1 || echo "ROBOREV_NOT_INSTALLED"
```

If roborev is not installed, guide the user:
- macOS: `brew install roborev` or `go install github.com/roborev/roborev@latest`
- Other: visit https://www.roborev.io for installation instructions

If gh CLI is not authenticated, ask user to run: `! gh auth login`

## Step 2: Project Analysis

Auto-detect project characteristics:

```bash
# Detect primary language
ls package.json go.mod pyproject.toml Cargo.toml pom.xml build.gradle 2>/dev/null

# Detect existing CI
ls .github/workflows/*.yml 2>/dev/null

# Detect existing config
ls review-to-pr.toml .roborev.toml 2>/dev/null

# Get repo name
gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null
```

If `review-to-pr.toml` already exists, enter **update mode** — only fill missing values, don't overwrite.

## Step 3: Agent & Model Selection

Scan for installed agents (in priority order):

```bash
# Check each agent
for agent in codex claude gemini copilot cursor opencode droid kilo kiro pi; do
  cmd=$agent
  [ "$agent" = "cursor" ] && cmd="agent"
  [ "$agent" = "kiro" ] && cmd="kiro-cli"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "✅ $agent"
  else
    echo "❌ $agent"
  fi
done
```

Present installed agents to user and ask:

1. **Default agent**: Which agent to use for reviews/fixes? (recommend first available)
2. **Default model** (optional): Leave empty for agent default. Reference:
   - codex: OpenAI models (o4-mini, o3, gpt-4.1)
   - claude: Anthropic models (claude-sonnet-4-6, claude-opus-4-6)
   - gemini: Google models (gemini-2.5-pro)
3. **Backup agent**: Recommend different ecosystem than primary. Option: "none"
4. **Backup model** (optional): Leave empty for agent default

## Step 4: Generate Configuration

Create `review-to-pr.toml` from user selections using the template at `${CLAUDE_PLUGIN_ROOT}/templates/review-to-pr.toml`.

Generate with the user's agent/model choices and project defaults.

Also:
- Copy `${CLAUDE_PLUGIN_ROOT}/lib/autofix.sh` to `scripts/review-to-pr-autofix.sh` and `chmod +x`
- Create `.review-to-pr/` directory
- Add `.review-to-pr/` to `.gitignore`
- Run `roborev install-hook` if roborev is available

## Step 5: Optional Enhancements

Ask the user:
1. **Generate CI workflow?** If `.github/workflows/` exists, offer to create a CI check workflow
2. **Append to CLAUDE.md?** Offer to add review-to-pr documentation section from `${CLAUDE_PLUGIN_ROOT}/templates/claude-md-section.md`

## Step 6: Verify

```bash
# Verify config
cat review-to-pr.toml

# Verify script
ls -la scripts/review-to-pr-autofix.sh

# Verify hook
ls .git/hooks/post-commit 2>/dev/null

# Verify state dir
ls -la .review-to-pr/
```

Print summary:
```
✅ review-to-pr 初始化完成！

  配置文件: review-to-pr.toml
  自动化脚本: scripts/review-to-pr-autofix.sh
  状态目录: .review-to-pr/
  审查 Agent: codex (备用: claude)

  下次 commit 将自动触发代码审查。
  使用 /review-fix 处理审查结果。
```
