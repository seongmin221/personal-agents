#!/usr/bin/env bash
# PreCompact hook for log-conversation — fires the skill when context is about to
# be compacted (e.g., on /clear or automatic compression). Session continues, so
# the counter is reset to 0 (not deleted) for a fresh 3-turn cycle post-compact.
set -u

# Recursion guard: spawned log-conversation sessions should not re-trigger.
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
  PreCompact "$CWD" "$TRANSCRIPT" "$LOG_FILE" >/dev/null 2>&1 &
disown

# Reset counter so the next 3-turn cycle starts fresh after compaction.
echo 0 > "$COUNT_FILE"
exit 0
