#!/usr/bin/env bash
# PreToolUse(Bash) ガード: 危険な操作を実行前に拒否する
#   入力: 標準入力の JSON（.tool_input.command / .cwd）  拒否: 終了コード 2 + 標準エラーに理由
#   jq が無くても動くよう python にフォールバック。判定不能時は安全側（拒否）に倒す
set -uo pipefail
export PATH="$HOME/.ai-harness/bin:$PATH"
input="$(cat)"
getf() {
  if command -v jq >/dev/null; then printf '%s' "$input" | jq -r "$1 // \"\"" | tr -d '\r'
  else
    local py; py="$(command -v python3 || command -v python || true)"
    [[ -n "$py" ]] || { echo "Blocked by guard.sh: jq / python が無く判定できません" >&2; exit 2; }
    printf '%s' "$input" | "$py" -c "import json,sys;d=json.load(sys.stdin);k='$1'.strip('.').split('.');v=d
for x in k: v=(v or {}).get(x) if isinstance(v,dict) else None
print(v or '')" | tr -d '\r'
  fi
}
cmd="$(getf .tool_input.command)"; cwd="$(getf .cwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"; MAIN="main"
block() { echo "Blocked by guard.sh: $1" >&2; exit 2; }

# 1. 既定ブランチへの直接 push / force push / 既定ブランチ削除
if grep -qE "git[[:space:]]+push" <<<"$cmd"; then
  grep -qE "(^|[[:space:]])(-f|--force|--force-with-lease)([[:space:]]|=|$)|[[:space:]]\+[^[:space:]]+" <<<"$cmd" && block "force push は禁止です"
  grep -qE "([[:space:]]|:)(refs/heads/)?${MAIN}([[:space:]]|$)" <<<"$cmd" && block "${MAIN} への直接 push・削除は禁止です。PR を作成してください"
  pos=($(sed -E 's/.*git[[:space:]]+push[[:space:]]*//; s/[;&|].*//' <<<"$cmd" | tr ' ' '\n' | grep -vE '^(-|$)' || true))
  ref="${pos[1]:-HEAD}"
  if [[ "$ref" == "HEAD" ]]; then
    cur="$(git -C "${cwd:-$ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [[ "$cur" == "$MAIN" ]] && block "${MAIN} ブランチ上での push は禁止です。/issue-start でブランチを作成してください"
  fi
fi
grep -qE "git[[:space:]]+branch[[:space:]]+-[dD][[:space:]]+${MAIN}([[:space:]]|$)" <<<"$cmd" && block "${MAIN} ブランチの削除は禁止です"

# 2. マージ・保護設定は人が行う
grep -qE "gh[[:space:]]+pr[[:space:]]+merge" <<<"$cmd" && block "マージは人が GitHub 上で Squash and Merge してください"
grep -qE "gh[[:space:]]+api.*(rulesets|branches/.*/protection)" <<<"$cmd" && block "ルールセット・保護設定の変更は禁止です"

# 3. Terraform: apply は issue- ワークスペースのみ、destroy 直接実行は禁止
if grep -qE "terraform([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+(apply|destroy|import|state[[:space:]]+(rm|mv|push))" <<<"$cmd"; then
  grep -qE "infra/(base|bootstrap)" <<<"$cmd $cwd" && block "共有基盤（infra/base, infra/bootstrap）は人が操作します"
  ws="${TF_WORKSPACE:-}"
  [[ -z "$ws" ]] && ws="$(terraform -chdir="$ROOT/infra/envs/issue" workspace show 2>/dev/null | tr -d '\r' || true)"
  [[ "$ws" =~ ^issue-[0-9]+$ ]] || block "issue-<番号> 以外のワークスペース（現在: ${ws:-不明}）での apply/destroy は禁止です"
  grep -qE "terraform([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+destroy" <<<"$cmd" \
    && block "terraform destroy の直接実行は禁止です。plan -destroy -out=destroy.tfplan → apply destroy.tfplan を使ってください"
fi

# 4. 破壊的な削除（許可リスト以外の rm -r）
if grep -qE "(^|[;&|[:space:]])rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)" <<<"$cmd"; then
  ok_re='^(\./)?(node_modules|dist|build|coverage|\.terraform|\.pytest_cache|\.ruff_cache|__pycache__|tmp|\.angular)(/.*)?$'
  targets="$(sed -E 's/.*(^|[;&|[:space:]])rm[[:space:]]+//; s/[;&|].*//' <<<"$cmd" | tr ' ' '\n' | grep -vE '^(-|$)' || true)"
  for t in $targets; do [[ "$t" =~ $ok_re ]] || block "rm -r の対象 '$t' は許可されていません"; done
fi

# 5. 機密ファイル
grep -qE "(cat|less|more|head|tail|type|grep|sed|awk|cp|scp)[[:space:]].*(\.env([[:space:]]|$|\.)|\.pem|id_rsa|\.aws/credentials|secrets/)" <<<"$cmd" \
  && block "機密ファイルへのアクセスは禁止です"

# 6. 共有基盤・IAM の変更系操作 / AWS プロファイル切り替え
grep -qE "aws[[:space:]]+(iam|organizations|rds|opensearch|es|ec2)[[:space:]]+(create|delete|put|update|modify|attach|detach|terminate)" <<<"$cmd" \
  && block "共有基盤・IAM の変更は禁止です"
grep -qE "(--profile[[:space:]=]|AWS_PROFILE=|AWS_ACCESS_KEY_ID=)" <<<"$cmd" && block "AWS の認証情報・プロファイルの切り替えは禁止です"

exit 0
