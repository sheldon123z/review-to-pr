## review-to-pr 自动化修复流水线

代码审查结果 → GitHub Issue → Worktree 隔离修复 → PR → 合并策略。

### 流程

```
审查完成 → /review-fix 或 /review-fix-all
  → 解析严重度 → 创建 GitHub Issue
  → git worktree add（隔离）→ Agent 修复 → git commit + push
  → gh pr create → 合并策略:
    low:  CI 通过后自动 squash merge
    medium/high/critical: 等待人工审查
```

### 命令

| 命令 | 说明 |
|------|------|
| `/review-fix [source] [job-id]` | 处理单个审查结果 |
| `/review-fix-all` | 批量处理所有 open 审查 |
| `/review-status` | 查看活跃修复任务状态 |
| `/review-cleanup [--all]` | 清理已完成的 worktree |
| `/review-to-pr-init` | 首次配置 |

### 循环阻断

| 层 | 机制 |
|---|---|
| 分支排除 | `fix/review-*` 不触发审查 |
| 提交前缀 | `🤖 fix: review-to-pr` 匹配排除 |
| Co-Author | `Co-Authored-By: review-to-pr` 兜底 |

### 配置

- `review-to-pr.toml` — 项目级配置（agent、合并策略、模板）
- `.review-to-pr/active.json` — 状态追踪（已加入 .gitignore）
