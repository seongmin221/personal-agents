#!/usr/bin/env bash
# Stop hook for log-conversation — 3-turn debounce.
# Fires the log-conversation skill every 3rd user turn, in the background.
# Stateless across invocations; per-session counter lives in ~/.claude/state/log-conversation/.
set -u

# Recursion guard: if this hook was triggered by a claude session that we spawned,
# do nothing. Prevents the spawned log-conversation session from firing this hook again.
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

COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))

if [ "$COUNT" -lt 3 ]; then
  echo "$COUNT" > "$COUNT_FILE"
  exit 0
fi

echo 0 > "$COUNT_FILE"

# Recursion is blocked by the env-var guard at the top. The shared helper
# handles OAuth auth, --add-dir for all vaults, and log-file append.
CLAUDE_HOOK_SPAWNED=1 nohup bash "$HOME/.claude/hooks/_spawn-log-conversation.sh" \
  Stop "$CWD" "$TRANSCRIPT" "$LOG_FILE" >/dev/null 2>&1 &
disown
exit 0
