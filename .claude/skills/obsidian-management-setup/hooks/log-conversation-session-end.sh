#!/usr/bin/env bash
# SessionEnd hook for log-conversation — unconditional final flush + counter cleanup.
set -u

# Recursion guard: spawned sessions' SessionEnd shouldn't re-fire logging.
if [ "${CLAUDE_HOOK_SPAWNED:-}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)
get() { python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$1',''))" <<< "$INPUT"; }

SESSION_ID=$(get session_id)
TRANSCRIPT=$(get transcript_path)
CWD=$(get cwd)

if [ -z "$SESSION_ID" ]; then exit 0; fi

STATE_DIR="$HOME/.claude/state/log-conversation"
mkdir -p "$STATE_DIR"
COUNT_FILE="$STATE_DIR/${SESSION_ID}.count"
LOG_FILE="$STATE_DIR/spawn.log"

CLAUDE_HOOK_SPAWNED=1 nohup bash "$HOME/.claude/hooks/_spawn-log-conversation.sh" \
  SessionEnd "$CWD" "$TRANSCRIPT" "$LOG_FILE" >/dev/null 2>&1 &
disown

rm -f "$COUNT_FILE"
exit 0
