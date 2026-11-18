#!/usr/bin/env bash
# Advisory PreToolUse reminder: a commit that changes user-visible repository
# material should also update the README's "Changes from upstream" list.
#
# This is a pure reminder. It never denies, never blocks a commit, and never
# changes pipeline behavior. It prints Claude's additionalContext JSON on stdout
# and exits 0 in every case, including every error (fail open).
# See docs/readme-reminder.md for the complete contract.
#
# Usage:
#   <PreToolUse JSON on stdin> | bin/fm-readme-reminder-pretool.sh [--claude]
#
# Silent (no output) when any of these holds:
#   - the command is not a `git commit`, or is a merge/fixup/squash/amend-no-edit commit;
#   - the commit message subject is a docs or README commit (`docs:`, `docs(...)`,
#     `Merge ...`, `fixup!`, `squash!`);
#   - the commit already includes README.md;
#   - the commit includes no user-visible material (bin/, skills, .claude/, AGENTS.md, ...);
#   - README.md has no "Changes from upstream" heading;
#   - the same staged-file set was already reminded about in this session;
#   - the payload came from another host, or jq/git is missing, or anything fails.
set -u

while [ "$#" -gt 0 ]; do
  case "$1" in
    --claude) shift ;;
    -h|--help)
      sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) exit 0 ;;
  esac
done

PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
# shellcheck source=bin/fm-hook-host-lib.sh disable=SC1091
. "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/fm-hook-host-lib.sh" 2>/dev/null || exit 0
fm_hook_payload_is_foreign_host "$PAYLOAD" && exit 0

CMD=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Cheap gate: a git commit invocation, optionally with global options before it.
printf '%s' "$CMD" | grep -Eq '(^|[;&|(]|&&)[[:space:]]*git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)' || exit 0

# Merge, fixup, squash, and no-edit commits carry no new README-worthy change.
case "$CMD" in
  *--fixup*|*--squash*|*--no-edit*) exit 0 ;;
esac
# Docs-only or merge subjects named in -m.
if printf '%s' "$CMD" | grep -Eiq -e "-m[[:space:]]*[\"']?(docs?(\\(|:|!)|merge[[:space:]:]|fixup!|squash!)"; then
  exit 0
fi

DIR=$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null) || exit 0
[ -n "$DIR" ] || DIR=${CLAUDE_PROJECT_DIR:-$PWD}
TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$TOP/README.md" ] || exit 0
grep -Eq '^#+[[:space:]]+Changes from upstream' "$TOP/README.md" 2>/dev/null || exit 0

FILES=$(git -C "$TOP" diff --cached --name-only 2>/dev/null) || exit 0
# `git commit -a` / `--all` also takes tracked modifications.
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])(--all|-[A-Za-z]*a[A-Za-z]*)([[:space:]]|$)'; then
  MODS=$(git -C "$TOP" diff --name-only 2>/dev/null) || exit 0
  FILES=$(printf '%s\n%s\n' "$FILES" "$MODS")
fi
FILES=$(printf '%s\n' "$FILES" | sed '/^$/d' | LC_ALL=C sort -u)
[ -n "$FILES" ] || exit 0

printf '%s\n' "$FILES" | grep -Eqx 'README\.md' && exit 0

# User-visible material: tooling, skills, hooks, harness config, the contract.
VISIBLE=$(printf '%s\n' "$FILES" | grep -E '^(bin/|\.agents/skills/|skills/|\.claude/|\.github/workflows/|AGENTS\.md$|skills-lock\.json$)' || true)
[ -n "$VISIBLE" ] || exit 0

# Once per distinct file set per session; the marker lives in the git dir, so the
# worktree's own cleanup removes it.
GIT_DIR=$(git -C "$TOP" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
SESSION=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "nosession"' 2>/dev/null) || SESSION=nosession
KEY=$(printf '%s\n%s\n' "$SESSION" "$FILES" | cksum | cut -d' ' -f1)
MARKDIR="$GIT_DIR/fm-readme-reminder"
[ -e "$MARKDIR/$KEY" ] && exit 0
mkdir -p "$MARKDIR" 2>/dev/null && : > "$MARKDIR/$KEY" 2>/dev/null

MSG='README reminder: this commit changes user-visible material but does not include README.md. If the change is user-visible (a harness, backend, skill, hook, or documented behavior added, changed, or removed), update the "Changes from upstream" list in README.md and add that change to this same branch. This is advisory only; the commit is not blocked.'
jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}' 2>/dev/null || exit 0
exit 0
