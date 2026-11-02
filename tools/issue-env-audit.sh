#!/usr/bin/env bash
# 稼働中の課題別環境を一覧し、クローズ済み課題の環境（片付け漏れ）を検出する
set -euo pipefail
export PATH="$HOME/.ai-harness/bin:$PATH"
cd "$(git rev-parse --show-toplevel)/infra/envs/issue"
terraform init -input=false >/dev/null
MAX=20; count=0; stale=0
printf "%-12s %-8s %s\n" WORKSPACE ISSUE STATUS
for ws in $(terraform workspace list | tr -d ' *\r' | grep -E '^issue-[0-9]+$' || true); do
  n="${ws#issue-}"; count=$((count+1))
  st="$(gh issue view "$n" --json state -q .state 2>/dev/null | tr -d '\r' || echo UNKNOWN)"
  mark=""; [[ "$st" != "OPEN" ]] && { mark="  ← 片付け候補 (/issue-cleanup $n)"; stale=$((stale+1)); }
  printf "%-12s #%-7s %s%s\n" "$ws" "$n" "$st" "$mark"
done
echo "稼働: $count / 上限 $MAX　片付け候補: $stale"
[[ $count -lt $MAX ]] || { echo "上限に達しています。新規の /issue-start は止めてください" >&2; exit 1; }
