#!/usr/bin/env bash
# review-to-pr autofix — 将审查结果转化为 GitHub Issue → Worktree 隔离修复 → PR
#
# 用法:
#   autofix.sh --source roborev --job-id 5
#   autofix.sh --source roborev --all
#   autofix.sh --source inline --review-file /tmp/review.md
#   autofix.sh --status
#   autofix.sh --cleanup [--all]
#   autofix.sh --dry-run ...

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_DIR="${PROJECT_ROOT}/.review-to-pr"
ACTIVE_FILE="${STATE_DIR}/active.json"
CONFIG_FILE="${PROJECT_ROOT}/review-to-pr.toml"

# 默认配置
DEFAULT_SOURCE="roborev"
MERGE_METHOD="squash"
CI_TIMEOUT=300
AUTO_MERGE_SEVERITY="low"
ISSUE_TITLE_TPL="🔍 代码审查: {subject}"
PR_TITLE_TPL="🤖 fix: 修复 #{issue_num} [{severity}]"
LANGUAGE="zh"

# 参数
SOURCE="" JOB_ID="" ALL_JOBS=false DRY_RUN=false
STATUS_MODE=false CLEANUP_MODE=false CLEANUP_ALL=false REVIEW_FILE=""
WORKTREES=""

load_config() {
  [ -f "$CONFIG_FILE" ] || return 0
  DEFAULT_SOURCE=$(grep -E '^default_source\s*=' "$CONFIG_FILE" 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' || echo "$DEFAULT_SOURCE")
  MERGE_METHOD=$(grep -E '^merge_method\s*=' "$CONFIG_FILE" 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' || echo "$MERGE_METHOD")
  CI_TIMEOUT=$(grep -E '^ci_timeout_seconds\s*=' "$CONFIG_FILE" 2>/dev/null | sed 's/.*=\s*//' || echo "$CI_TIMEOUT")
  LANGUAGE=$(grep -E '^language\s*=' "$CONFIG_FILE" 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' || echo "$LANGUAGE")
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --source) SOURCE="$2"; shift 2 ;;
      --job-id) JOB_ID="$2"; shift 2 ;;
      --all) ALL_JOBS=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --status) STATUS_MODE=true; shift ;;
      --cleanup) CLEANUP_MODE=true; shift ;;
      --cleanup-all) CLEANUP_MODE=true; CLEANUP_ALL=true; shift ;;
      --review-file) REVIEW_FILE="$2"; shift 2 ;;
      *) echo "未知参数: $1"; exit 1 ;;
    esac
  done
  [ -z "$SOURCE" ] && SOURCE="$DEFAULT_SOURCE"
}

get_repo() {
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || \
    git remote get-url origin 2>/dev/null | sed 's/.*github.com[:/]\(.*\)\.git/\1/' || \
    echo "unknown/unknown"
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
  [ -f "$ACTIVE_FILE" ] || echo '[]' > "$ACTIVE_FILE"
  if [ -f "${PROJECT_ROOT}/.gitignore" ]; then
    grep -qxF '.review-to-pr/' "${PROJECT_ROOT}/.gitignore" 2>/dev/null || echo '.review-to-pr/' >> "${PROJECT_ROOT}/.gitignore"
  fi
}

parse_severity() {
  local text="$1"
  local en_sev
  en_sev=$(echo "$text" | grep -iE '[Ss]everity|严重度' | head -1 \
    | sed 's/.*[Ss]everity[^a-zA-Z]*\([a-zA-Z]*\).*/\1/' | tr '[:upper:]' '[:lower:]' \
    | grep -oE '^(low|medium|high|critical|info)$' || true)
  if [ -n "$en_sev" ]; then echo "$en_sev"; return; fi
  local zh_sev
  zh_sev=$(echo "$text" | grep -E '严重度' | head -1 | grep -oE '(低|中|高|严重)' | head -1 || true)
  case "$zh_sev" in
    低) echo "low" ;; 中) echo "medium" ;; 高) echo "high" ;; 严重) echo "critical" ;; *) echo "unknown" ;;
  esac
}

is_processed() {
  [ -f "$ACTIVE_FILE" ] && python3 -c "
import json,sys
data=json.load(open('$ACTIVE_FILE'))
sys.exit(0 if any(r['review_id']=='$1' for r in data) else 1)" 2>/dev/null
}

record_active() {
  python3 -c "
import json,datetime
f='$ACTIVE_FILE'; data=json.load(open(f))
data.append({'review_id':'$1','pr_url':'$2','pr_num':int('$3'),'issue_num':int('$4'),
  'worktree':'$5','branch':'$6','severity':'$7',
  'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat()})
json.dump(data,open(f,'w'),indent=2)"
}

remove_active() {
  python3 -c "
import json
f='$ACTIVE_FILE'; data=json.load(open(f))
data=[r for r in data if r['review_id']!='$1']
json.dump(data,open(f,'w'),indent=2)"
}

wait_for_ci() {
  local pr_num="$1" repo="$2" elapsed=0
  echo "  ⏳ 等待 CI (PR #${pr_num})..."
  while [ "$elapsed" -lt "$CI_TIMEOUT" ]; do
    local st; st=$(gh pr checks "$pr_num" --repo "$repo" 2>&1 || echo "pending")
    echo "$st" | grep -qiE 'fail|error' && { echo "  ❌ CI 失败"; return 1; }
    echo "$st" | grep -qiE 'pass|success' && ! echo "$st" | grep -qiE 'pending|running' && { echo "  ✅ CI 通过!"; return 0; }
    sleep 15; elapsed=$((elapsed + 15)); echo "  ⏳ ${elapsed}s/${CI_TIMEOUT}s"
  done
  echo "  ⏰ CI 超时"; return 1
}

cleanup_wt() {
  local wt="$1" branch="$2"
  [ -d "$wt" ] && { git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"; }
  git branch -D "$branch" 2>/dev/null || true
}

trap 'for wt in $WORKTREES; do [ -d "$wt" ] && { git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"; }; done' EXIT

get_roborev_jobs() {
  roborev fix --list 2>&1 | awk '/^[[:space:]]*Job #[0-9]+[[:space:]]*$/{
    l=$0; sub(/^[[:space:]]*Job #/,"",l); sub(/[[:space:]]*$/,"",l); j=j(j?" ":"")l} END{print j}'
}

get_roborev_meta() {
  local jid="$1" list_out
  list_out=$(roborev fix --list 2>&1 || true)
  local block; block=$(printf '%s\n' "$list_out" | awk -v j="$jid" '
    /^[[:space:]]*Job #[0-9]+[[:space:]]*$/{c=$0;sub(/^[[:space:]]*Job #/,"",c);sub(/[[:space:]]*$/,"",c);b=(c==j);next} b{print}')
  COMMIT_SHA=$(printf '%s\n' "$block" | awk '/Git Ref:/{print $NF;exit}')
  SUBJECT=$(printf '%s\n' "$block" | sed -n 's/^[[:space:]]*Subject:[[:space:]]*//p' | head -1)
  [ -z "$COMMIT_SHA" ] && COMMIT_SHA="unknown"
  [ -z "$SUBJECT" ] && SUBJECT="Review #${jid}"
}

lazy_cleanup() {
  [ -f "$ACTIVE_FILE" ] || return 0
  local repo; repo=$(get_repo)
  python3 -c "
import json
data=json.load(open('$ACTIVE_FILE'))
for r in data: print(f\"{r['review_id']}|{r['pr_num']}|{r['worktree']}|{r['branch']}\")" 2>/dev/null | \
  while IFS='|' read -r rid pn wt br; do
    local state; state=$(gh pr view "$pn" --repo "$repo" --json state -q .state 2>/dev/null || echo "UNKNOWN")
    case "$state" in MERGED|CLOSED) echo "  🧹 清理 PR #${pn} (${state})"; cleanup_wt "$wt" "$br"; remove_active "$rid" ;; esac
  done
}

show_status() {
  ensure_state_dir; lazy_cleanup
  [ "$(cat "$ACTIVE_FILE" 2>/dev/null)" = "[]" ] && { echo "✅ 没有活跃的修复任务。"; return; }
  echo "📋 活跃的修复任务:"; echo ""
  python3 -c "
import json
for r in json.load(open('$ACTIVE_FILE')):
  print(f\"  #{r['pr_num']} [{r['severity']}] {r['pr_url']}\")
  print(f\"     分支: {r['branch']}  Worktree: {r['worktree']}\n\")"
}

force_cleanup() {
  ensure_state_dir
  if $CLEANUP_ALL; then
    echo "🧹 强制清理所有 worktree..."
    python3 -c "
import json
for r in json.load(open('$ACTIVE_FILE')):
  print(f\"{r['review_id']}|{r['worktree']}|{r['branch']}\")" 2>/dev/null | \
    while IFS='|' read -r rid wt br; do cleanup_wt "$wt" "$br"; remove_active "$rid"; echo "  ✅ ${br}"; done
  else lazy_cleanup; fi
  echo "🎉 清理完成。"
}

process_review() {
  local source="$1" jid="$2" repo; repo=$(get_repo)
  local rid="${source}:${jid}"

  echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "处理: ${rid}"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  is_processed "$rid" && { echo "  ⏭️ 已处理"; return; }

  local review
  case "$source" in
    roborev) review=$(roborev show "$jid" 2>&1 || true) ;;
    inline) [ -f "$REVIEW_FILE" ] && review=$(cat "$REVIEW_FILE") || { echo "❌ 文件不存在"; return; } ;;
    *) echo "❌ 不支持: $source"; return ;;
  esac

  local severity; severity=$(parse_severity "$review"); echo "  严重度: ${severity}"

  COMMIT_SHA="unknown"; SUBJECT="Review #${jid}"
  [ "$source" = "roborev" ] && get_roborev_meta "$jid"
  echo "  提交: ${COMMIT_SHA} - ${SUBJECT}"

  $DRY_RUN && { echo "  [dry-run] 将创建 Issue+PR (${severity})"; echo "$review" | head -5; return; }

  local issue_title; issue_title=$(echo "$ISSUE_TITLE_TPL" | sed "s/{subject}/${SUBJECT}/g")
  local issue_url; issue_url=$(gh issue create --repo "$repo" --title "$issue_title" --label "review-to-pr,automated" \
    --body "$(printf '## 代码审查报告\n\n**提交**: `%s`\n**来源**: %s #%s\n**严重度**: %s\n\n%s\n\n---\n> 由 review-to-pr 自动创建。' \
      "$COMMIT_SHA" "$source" "$jid" "$severity" "$review")")
  local issue_num; issue_num=$(echo "$issue_url" | sed 's/.*\///')
  echo "  ✅ Issue #${issue_num}"

  local branch="fix/review-${jid}" worktree="/tmp/review-fix-${jid}"
  WORKTREES="${WORKTREES} ${worktree}"

  [ -d "$worktree" ] && { echo "  🧹 清理残留"; cleanup_wt "$worktree" "$branch"; }

  echo "  📦 Worktree: ${worktree}"
  if ! git worktree add "$worktree" -b "$branch" HEAD 2>/dev/null; then
    git worktree add "$worktree" "$branch" 2>/dev/null || { echo "  ❌ Worktree 失败"; WORKTREES="${WORKTREES/ $worktree/}"; return; }
  fi

  echo "  🔧 修复中..."
  local fix_ok=true
  if [ "$source" = "roborev" ]; then
    (cd "$worktree" && roborev fix "$jid") || fix_ok=false
  else
    echo "$review" > "${worktree}/.review-report.md"
    echo "  ℹ️ 报告已写入 worktree，等待 fixer agent"
  fi
  cd "$PROJECT_ROOT"

  $fix_ok || { echo "  ⚠️ 修复失败"; cleanup_wt "$worktree" "$branch"; WORKTREES="${WORKTREES/ $worktree/}"; return; }

  [ -z "$(git -C "$worktree" status --porcelain)" ] && { echo "  ℹ️ 无变更"; cleanup_wt "$worktree" "$branch"; WORKTREES="${WORKTREES/ $worktree/}"; return; }

  git -C "$worktree" add -A
  git -C "$worktree" rm --cached .review-report.md 2>/dev/null || true
  git -C "$worktree" commit -m "$(printf '🤖 fix: review-to-pr 自动修复 #%s\n\nCloses #%s\n\nCo-Authored-By: review-to-pr <noreply@review-to-pr>' "$jid" "$issue_num")"
  git -C "$worktree" push -u origin "$branch"

  local pr_title; pr_title=$(echo "$PR_TITLE_TPL" | sed "s/{issue_num}/${issue_num}/g; s/{severity}/${severity}/g")
  local merge_note; echo "$AUTO_MERGE_SEVERITY" | grep -qw "$severity" && merge_note="CI 通过后自动合并" || merge_note="需要人工审查"

  local pr_url; pr_url=$(gh pr create --repo "$repo" --title "$pr_title" --base main --head "$branch" \
    --body "$(printf '## 自动修复\n\n**Issue**: #%s\n**来源**: %s #%s\n**严重度**: %s\n\n%s\n\n---\n> review-to-pr | %s' \
      "$issue_num" "$source" "$jid" "$severity" "$review" "$merge_note")")
  echo "  ✅ PR: ${pr_url}"
  local pr_num; pr_num=$(echo "$pr_url" | sed 's/.*\///')

  if echo "$AUTO_MERGE_SEVERITY" | grep -qw "$severity"; then
    echo "  🟢 自动合并..."
    if wait_for_ci "$pr_num" "$repo"; then
      local msub="🤖 fix: review-to-pr 自动修复 #${jid} (Closes #${issue_num})"
      gh pr merge "$pr_url" --repo "$repo" --"$MERGE_METHOD" --delete-branch --subject "$msub" 2>&1 && {
        echo "  ✅ 已合并"
        gh issue close "$issue_num" --repo "$repo" --comment "✅ 已自动合并。" 2>/dev/null || true
      } || echo "  ⚠️ 合并失败"
    fi
    cleanup_wt "$worktree" "$branch"; WORKTREES="${WORKTREES/ $worktree/}"
  else
    echo "  🟡 ${severity} — 等待人工审查"
    record_active "$rid" "$pr_url" "$pr_num" "$issue_num" "$worktree" "$branch" "$severity"
    WORKTREES="${WORKTREES/ $worktree/}"
  fi
}

main() {
  load_config; parse_args "$@"; ensure_state_dir; lazy_cleanup
  $STATUS_MODE && { show_status; exit 0; }
  $CLEANUP_MODE && { force_cleanup; exit 0; }

  local job_ids=""
  if [ -n "$JOB_ID" ]; then job_ids="$JOB_ID"
  elif $ALL_JOBS; then
    [ "$SOURCE" = "roborev" ] && job_ids=$(get_roborev_jobs) || { echo "❌ --all 仅支持 roborev"; exit 1; }
  else echo "❌ 需要 --job-id 或 --all"; exit 1; fi

  job_ids=$(echo "$job_ids" | xargs)
  [ -z "$job_ids" ] && { echo "✅ 无待处理。"; exit 0; }

  local total; total=$(echo "$job_ids" | wc -w | tr -d ' ')
  echo "📋 ${total} 个待处理: ${job_ids}"
  for jid in $job_ids; do process_review "$SOURCE" "$jid"; done
  echo ""; echo "🎉 完成。"
}

main "$@"
