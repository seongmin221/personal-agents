#!/usr/bin/env bash
# PostToolUse hook (Bash matcher): paired with gh-switch.sh. After a Bash
# command completes, if it was git/gh-related, restore the github.com keyring
# account that was active before gh-switch.sh flipped it to seongmin221.

set -uo pipefail

TARGET_USER="seongmin221"
STATE_FILE="/tmp/claude-personal-agents-gh-prev"

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [ -z "$command" ]; then
  exit 0
fi

if ! printf '%s' "$command" | grep -qE '(^|[;&|]+[[:space:]]*)(git|gh)([[:space:]]|$)'; then
  exit 0
fi

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

prev=$(cat "$STATE_FILE")
rm -f "$STATE_FILE"

if [ -z "$prev" ] || [ "$prev" = "$TARGET_USER" ]; then
  exit 0
fi

if env -u GITHUB_TOKEN gh auth switch -h github.com -u "$prev" >/dev/null 2>&1; then
  echo "[gh-restore] github.com keyring -> $prev" >&2
else
  echo "[gh-restore] WARNING: failed to restore github.com account to $prev" >&2
fi
