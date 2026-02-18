#!/bin/bash
LOG_DIR="$HOME/.claude/logs/permissions"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# 重要フィールドだけ抽出してサマリーを作成
SUMMARY=$(echo "$INPUT" | jq -c '.tool_input // {} | {
  command: .command,
  file_path: .file_path,
  url: .url,
  skill: .skill
} | with_entries(select(.value != null))' 2>/dev/null || echo "{}")

echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"tool\":\"$TOOL_NAME\",\"summary\":$SUMMARY}" >> "$LOG_FILE"

exit 0
