#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): before a Bash command runs, if the command
# is git/gh-related, save the currently active github.com keyring account and
# switch to seongmin221. The paired PostToolUse hook (gh-restore.sh) flips it
# back once the command completes.

set -uo pipefail

TARGET_USER="seongmin221"
STATE_FILE="/tmp/claude-personal-agents-gh-prev"

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [ -z "$command" ]; then
  exit 0
fi

# Trigger only when `git` or `gh` is invoked as a top-level command — i.e. at
# the start of the command string or right after a shell separator (; && || |).
# Avoids false positives like `echo git` or paths containing "git".
if ! printf '%s' "$command" | grep -qE '(^|[;&|]+[[:space:]]*)(git|gh)([[:space:]]|$)'; then
  exit 0
fi

# Read the keyring's active github.com account with GITHUB_TOKEN stripped so
# gh reports the keyring state rather than the env-token virtual entry.
prev=$(env -u GITHUB_TOKEN gh auth status 2>&1 | awk '
  /^[^ ]/ { host=$1; acct=""; next }
  host=="github.com" && /Logged in to github\.com account/ {
    for (i=1; i<=NF; i++) if ($i=="account") { acct=$(i+1); break }
    next
  }
  host=="github.com" && acct!="" && /Active account: true/ { print acct; exit }
')

printf '%s' "$prev" > "$STATE_FILE"

if [ "$prev" = "$TARGET_USER" ]; then
  exit 0
fi

# `gh auth switch` refuses to run while GITHUB_TOKEN is set, so strip it here.
if env -u GITHUB_TOKEN gh auth switch -h github.com -u "$TARGET_USER" >/dev/null 2>&1; then
  echo "[gh-switch] github.com keyring -> $TARGET_USER (was: ${prev:-<none>})" >&2
else
  echo "[gh-switch] WARNING: failed to switch github.com to $TARGET_USER" >&2
fi
