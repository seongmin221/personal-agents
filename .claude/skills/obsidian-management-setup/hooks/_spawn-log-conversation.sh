#!/usr/bin/env bash
# Shared helper used by log-conversation-{stop,session-end,precompact}.sh.
# Spawns a detached headless `claude -p "/log-conversation"` with the correct
# --add-dir set. Must be invoked with CLAUDE_HOOK_SPAWNED=1 in env (the hook
# scripts do this) so the spawned session's own Stop/SessionEnd hooks no-op.
#
# Usage: _spawn-log-conversation.sh <event-name> <cwd> <transcript> <log-file>
set -u

EVENT="$1"
CWD="$2"
TRANSCRIPT="$3"
LOG_FILE="$4"

# Build --add-dir args: always ~/.claude (for CLAUDE.md) and cwd (the session's
# working dir). Then add every vault path from ~/.claude/CLAUDE.md so the skill
# can read the target vault's OBSIDIAN.md and write to today's daily note,
# regardless of which vault the cwd resolves to.
ADD_DIRS=(--add-dir "$HOME/.claude" --add-dir "$CWD")
while IFS= read -r vault; do
  [ -n "$vault" ] && ADD_DIRS+=(--add-dir "$vault")
done < <(python3 - <<'PY'
import os, re, sys
home = os.environ['HOME']
try:
    content = open(f'{home}/.claude/CLAUDE.md').read()
except FileNotFoundError:
    sys.exit()
m = re.search(r'###\s*작업\s*-\s*vault\s*매핑.*?(?=###|\Z)', content, re.S)
if not m:
    sys.exit()
for line in m.group(0).splitlines():
    line = line.strip()
    if not line.startswith('|') or '|--' in line or '작업' in line:
        continue
    parts = [p.strip() for p in line.split('|')]
    # parts[0]='' (before first |), parts[1]=label, parts[2]=path, parts[3]=''
    if len(parts) >= 4 and parts[2]:
        p = parts[2]
        if p == '~':
            p = home
        elif p.startswith('~/'):
            p = home + p[1:]
        print(p)
PY
)

PROMPT="/log-conversation

Invocation context:
- cwd: ${CWD}
- transcript file: ${TRANSCRIPT}"

{
  echo
  echo "--- ${EVENT} spawn at $(date -u +%Y-%m-%dT%H:%M:%SZ) cwd=${CWD} ---"
  echo "add-dirs: ${ADD_DIRS[*]}"
  echo "$PROMPT" | claude -p \
    --model claude-haiku-4-5 \
    --permission-mode acceptEdits \
    "${ADD_DIRS[@]}"
} >> "$LOG_FILE" 2>&1
