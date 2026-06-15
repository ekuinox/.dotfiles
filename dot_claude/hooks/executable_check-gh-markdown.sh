#!/usr/bin/env bash
# PreToolUse hook (Bash matcher).
# gh pr / gh issue の create / edit / comment 実行時、コマンド文字列に
# Markdown の強調 (**) やコードフェンス (```) が含まれていたら実行前に確認 (ask) を促す。
# 本物のコードを貼る正当なケースもあるためブロックはしない。

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# gh pr / gh issue の create / edit / comment 以外は素通り。
if ! printf '%s' "$command" | grep -Eq 'gh[[:space:]]+(pr|issue)[[:space:]]+(create|edit|comment)'; then
  exit 0
fi

reasons=()
if printf '%s' "$command" | grep -q '\*\*'; then
  reasons+=("Markdown の強調 (**) が含まれています。強調は無視すると危険な要点のみに限ること。")
fi
if printf '%s' "$command" | grep -qF '```'; then
  reasons+=("コードフェンス (\`\`\`) が含まれています。コードでないものにコードブロックを使わないこと。本当にコードを貼る場合のみ承認してください。")
fi

if [ ${#reasons[@]} -eq 0 ]; then
  exit 0
fi

reason="PR/issue 本文の書式を確認してください: $(printf '%s ' "${reasons[@]}")"

jq -nc --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r
  }
}'
