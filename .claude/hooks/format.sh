#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit): 編集したファイルを自動整形（失敗しても作業は止めない）
export PATH="$HOME/.ai-harness/bin:$PATH"
input="$(cat)"
if command -v jq >/dev/null; then f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' | tr -d '\r')"
else f="$(printf '%s' "$input" | { python3 2>/dev/null || python; } -c 'import json,sys;print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null | tr -d '\r')"; fi
command -v cygpath >/dev/null && [[ "$f" =~ ^[A-Za-z]: ]] && f="$(cygpath -u "$f")"
[[ -n "$f" && -f "$f" ]] || exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
run() { "$@" >/dev/null 2>&1 || true; }
case "$f" in
  *.py) if command -v ruff >/dev/null; then run ruff format "$f"; run ruff check --fix "$f"; fi ;;
  *.ts|*.js|*.mjs|*.html|*.scss|*.css|*.json)
    [[ "$f" == *"/.claude/"* || "$f" == *"/.vscode/"* ]] && exit 0
    if [[ -x "$ROOT//node_modules/.bin/prettier" ]]; then run "$ROOT//node_modules/.bin/prettier" --write "$f"; fi ;;
  *.tf|*.tfvars) command -v terraform >/dev/null && run terraform fmt "$f" ;;
  *.sh) command -v sed >/dev/null && run sed -i 's/\r$//' "$f" ;;
esac
exit 0
