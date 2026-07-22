#!/usr/bin/env bash
# 一键：用 DeepSeek 根据 diff 生成中文 commit message，并 commit + push
# 用法:
#   ./one-click-git-push.sh           # 生成消息 → 提交 → 推送
#   ./one-click-git-push.sh --dry-run # 只打印消息，不提交
#   ./one-click-git-push.sh --no-push # 只提交，不推送
#   ./one-click-git-push.sh -m "自定义消息"  # 跳过 AI，直接用给定消息
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

ENV_FILE="${ROOT}/.git-ai.env"
DRY_RUN=0
NO_PUSH=0
CUSTOM_MSG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    -m|--message)
      CUSTOM_MSG="${2:-}"
      if [[ -z "$CUSTOM_MSG" ]]; then
        echo "错误: -m/--message 需要提供提交说明" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "未知参数: $1（用 --help 查看用法）" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d .git ]]; then
  echo "错误: 当前目录不是 git 仓库" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "错误: 需要 curl" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "错误: 需要 jq（brew install jq）" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "错误: 需要 python3" >&2
  exit 1
fi

# 加载本地配置；环境变量优先
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
fi

DEEPSEEK_API_BASE="${DEEPSEEK_API_BASE:-https://api.deepseek.com/v1}"
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-}"
DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-v4-flash}"

if [[ -z "$CUSTOM_MSG" && -z "$DEEPSEEK_API_KEY" ]]; then
  echo "错误: 未配置 DEEPSEEK_API_KEY" >&2
  echo "请复制 .git-ai.env.example 为 .git-ai.env 并填入 Key，或 export DEEPSEEK_API_KEY=..." >&2
  exit 1
fi

# 排除不应提交的敏感文件提示
sensitive_hits="$(git status --porcelain | awk '{print $2}' | grep -E '(^|/)\.env$|\.pem$|credentials\.json$|\.git-ai\.env$' || true)"
if [[ -n "$sensitive_hits" ]]; then
  echo "警告: 工作区包含疑似敏感文件，请确认是否应提交:" >&2
  echo "$sensitive_hits" >&2
fi

if [[ -z "$(git status --porcelain)" ]]; then
  echo "没有可提交的变更。"
  if [[ "$NO_PUSH" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      echo "==> 无本地改动，尝试 push ${branch} ..."
      git push
    else
      echo "==> 无上游分支，尝试 git push -u origin ${branch} ..."
      git push -u origin HEAD
    fi
  fi
  exit 0
fi

truncate_text() {
  local max="${1:-80000}"
  python3 -c "
import sys
data = sys.stdin.read()
max_n = int(sys.argv[1])
if len(data) <= max_n:
    sys.stdout.write(data)
else:
    sys.stdout.write(data[:max_n])
    sys.stdout.write('\n\n...[已截断，原长度 %d 字符]...\n' % len(data))
" "$max"
}

collect_context() {
  echo "### git status"
  git status --porcelain
  echo
  echo "### 最近提交（风格参考）"
  git log -8 --pretty=format:'%s' 2>/dev/null || true
  echo
  echo
  echo "### staged diff"
  git diff --cached | truncate_text 40000
  echo
  echo "### unstaged diff（含未跟踪文件内容摘要）"
  # 未跟踪文件用 git add -N 不可取；对未跟踪仅列路径，已跟踪用 diff
  git diff | truncate_text 40000
  echo
  echo "### 未跟踪文件"
  git ls-files --others --exclude-standard
}

generate_commit_message() {
  local context payload response msg
  context="$(collect_context)"

  payload="$(python3 -c '
import json, sys
context = sys.stdin.read()
system = """你是本仓库的 Git 提交信息助手。根据变更生成一条 commit message。

硬性要求：
1. 必须使用简体中文（类型前缀可用英文）。
2. 第一行标题格式：`类型: 中文描述`，类型取 feat/fix/perf/docs/chore/refactor/test 等之一。
3. 标题不超过 50 个汉字或等效长度，语气简洁，只写一个主题。
4. 若有必要，空一行后用 1–3 行中文正文说明「为什么」，不要罗列文件名。
5. 只输出提交信息本身，不要用 markdown 代码块，不要引号包裹，不要解释。"""
user = "请根据以下 git 变更生成提交信息：\n\n" + context
print(json.dumps({
    "model": sys.argv[1],
    "temperature": 0.2,
    "messages": [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ],
}, ensure_ascii=False))
' "$DEEPSEEK_MODEL" <<<"$context")"

  echo "==> 正在调用 DeepSeek (${DEEPSEEK_MODEL}) 生成提交信息 ..." >&2
  response="$(curl -sS --fail-with-body \
    "${DEEPSEEK_API_BASE%/}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
    -d "$payload")" || {
      echo "错误: DeepSeek API 调用失败" >&2
      echo "$response" >&2
      exit 1
    }

  msg="$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^```[a-zA-Z]*//' -e 's/^```//' -e 's/```$//')"
  if [[ -z "$msg" || "$msg" == "null" ]]; then
    echo "错误: 未能从 API 响应中解析出提交信息" >&2
    echo "$response" | jq . 2>/dev/null || echo "$response"
    exit 1
  fi
  printf '%s' "$msg"
}

if [[ -n "$CUSTOM_MSG" ]]; then
  COMMIT_MSG="$CUSTOM_MSG"
else
  COMMIT_MSG="$(generate_commit_message)"
fi

echo
echo "---------- 提交信息 ----------"
printf '%s\n' "$COMMIT_MSG"
echo "------------------------------"
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run：已跳过 commit / push"
  exit 0
fi

echo "==> git add -A"
git add -A

# 再次确认暂存区非空（例如仅有被 ignore 的文件）
if [[ -z "$(git diff --cached --name-only)" ]]; then
  echo "错误: 暂存区为空（可能变更均被 .gitignore 忽略）" >&2
  exit 1
fi

echo "==> git commit"
git commit -m "$COMMIT_MSG"

if [[ "$NO_PUSH" -eq 1 ]]; then
  echo "==> 已跳过 push（--no-push）"
  git status -sb
  exit 0
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
echo "==> git push (${branch})"
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  git push
else
  git push -u origin HEAD
fi

echo "==> 完成"
git status -sb
git log -1 --oneline
