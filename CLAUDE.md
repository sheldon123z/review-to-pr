# review-to-pr

Claude Code Plugin — 将代码审查结果自动转化为 GitHub Issue → Worktree 隔离修复 → PR 的完整流水线。

GitHub: https://github.com/sheldon123z/review-to-pr

## 架构

```
审查工具 (roborev / inline)
  → review-to-pr 插件
    → GitHub Issue (可追溯)
    → git worktree (隔离修复)
    → fixer agent / roborev fix (代码修复)
    → gh pr create (PR)
    → 合并策略 (low=自动, medium+=人工)
```

## 项目结构

```
review-to-pr/
├── .claude-plugin/plugin.json    # 插件清单 (name, version, metadata)
├── skills/
│   ├── init/SKILL.md             # /review-to-pr-init — 交互式初始化
│   ├── fix/SKILL.md              # /review-fix — 单个审查 → Issue → PR
│   ├── fix-all/SKILL.md          # /review-fix-all — 批量处理
│   ├── status/SKILL.md           # /review-status — 查看活跃任务状态
│   └── cleanup/SKILL.md          # /review-cleanup — 清理 worktree
├── agents/fixer.md               # worktree 内修复专用 agent
├── hooks/hooks.json              # commit 前自动 pull
├── lib/autofix.sh                # 核心自动化脚本
├── templates/
│   ├── review-to-pr.toml         # 项目配置模板
│   └── claude-md-section.md      # CLAUDE.md 文档段模板
├── .gitignore
├── LICENSE                       # MIT
└── README.md
```

## 核心流程

```
/review-fix [source] [job-id]
  ├─ 获取审查结果 + 解析 severity (英文优先, 中文 fallback)
  ├─ 去重检查 (.review-to-pr/active.json)
  ├─ gh issue create (标签: review-to-pr, automated)
  ├─ git worktree add /tmp/review-fix-<id> (隔离)
  ├─ roborev fix / fixer agent (修复)
  ├─ git commit (Closes #N) + push + gh pr create
  └─ 合并策略:
      low → wait_for_ci → squash merge --subject (匹配排除规则)
      medium/high/critical → 保留 worktree, 记录到 active.json
```

## 循环阻断 (三层防护)

| 层 | 机制 | 覆盖场景 |
|---|---|---|
| 分支排除 | `fix/review-*` | worktree 修复提交不触发审查 |
| 提交前缀 | `🤖 fix: review-to-pr` | commit + squash merge 标题匹配 |
| Co-Author | `Co-Authored-By: review-to-pr` | commit body 兜底 |

## 状态追踪与清理

- `.review-to-pr/active.json` — 记录 medium/high PR 的 worktree 映射
- 惰性清理: 每次运行 /review-fix、/review-status 时自动检查已合并 PR
- `/review-cleanup` — 手动清理; `--all` 强制清理所有

## 开发命令

```bash
# 本地测试插件
claude --plugin-dir /path/to/review-to-pr

# 安装到 Claude Code
claude plugin add https://github.com/sheldon123z/review-to-pr

# 在目标项目中初始化
/review-to-pr-init

# 处理审查
/review-fix roborev <job-id>      # 单个
/review-fix-all                    # 批量
/review-status                     # 查看状态
/review-cleanup                    # 清理
```

## 依赖

| 依赖 | 必需 | 说明 |
|------|------|------|
| Claude Code | 是 | 插件宿主 |
| git | 是 | worktree + 分支管理 |
| gh CLI | 是 | Issue/PR 创建、合并 |
| python3 | 是 | active.json 状态管理 |
| roborev | 否 | 默认审查来源 (可用 inline 替代) |

## 配置

目标项目中的 `review-to-pr.toml`:

```toml
[review]
agent = "codex"                    # 审查/修复 agent
model = ""                         # 留空=默认模型
backup_agent = "claude"            # 备用 agent

[merge]
auto_merge_severity = ["low"]      # 自动合并的严重度
ci_timeout_seconds = 300
merge_method = "squash"

[templates]
language = "zh"                    # zh / en
```

## Fixer Agent 权限边界

| 允许 | 禁止 |
|------|------|
| 读写 worktree 内文件 | 修改主工作目录 |
| 在 worktree 中运行测试 | push 到 main |
| git add + commit (worktree 内) | 修改 .env / secrets |
| 安装依赖 | rm -rf / DROP TABLE |
