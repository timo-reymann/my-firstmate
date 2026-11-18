#!/usr/bin/env bash
# shellcheck disable=SC1091
# Behavior tests for the advisory README reminder hook (docs/readme-reminder.md).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_git_identity fmtest fmtest@example.invalid
TMP_ROOT=$(fm_test_tmproot fm-readme-reminder)
HOOK="$ROOT/bin/fm-readme-reminder-pretool.sh"

# make_repo <dir> [with-heading]: a git repo with a README and one commit.
make_repo() {
  local dir=$1 heading=${2:-yes}
  git init -q "$dir"
  if [ "$heading" = yes ]; then
    printf '# T\n\n## Changes from upstream\n\n- x\n' > "$dir/README.md"
  else
    printf '# T\n' > "$dir/README.md"
  fi
  mkdir -p "$dir/bin" "$dir/docs"
  : > "$dir/bin/a.sh"
  : > "$dir/docs/a.md"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
}

# run_hook <repo> <command> [session]: prints stdout, sets RC.
run_hook() {
  local repo=$1 cmd=$2 session=${3:-s1} payload
  payload=$(jq -cn --arg c "$cmd" --arg d "$repo" --arg s "$session" \
    '{tool_input:{command:$c},cwd:$d,session_id:$s}')
  OUT=$(printf '%s' "$payload" | bash "$HOOK" --claude 2>/dev/null)
  RC=$?
}

assert_silent() {
  [ "$RC" -eq 0 ] || fail "$1: exit $RC"
  [ -z "$OUT" ] || fail "$1: expected no output, got: $OUT"
}

test_fires_on_user_visible_commit() {
  local r=$TMP_ROOT/fires
  make_repo "$r"
  echo x >> "$r/bin/a.sh"; git -C "$r" add bin/a.sh
  run_hook "$r" 'git commit -m "feat: thing"'
  [ "$RC" -eq 0 ] || fail "exit $RC"
  printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"
    and (.hookSpecificOutput.additionalContext | contains("Changes from upstream"))
    and (has("permissionDecision") | not)' >/dev/null || fail "bad JSON: $OUT"
  run_hook "$r" 'git commit -m "feat: thing"'
  assert_silent "second identical commit attempt in the same session"
  run_hook "$r" 'git commit -m "feat: thing"' other-session
  [ -n "$OUT" ] || fail "a new session should be reminded again"
  pass "fires once per staged set per session as valid advisory JSON"
}

test_commit_all_includes_tracked_modifications() {
  local r=$TMP_ROOT/all
  make_repo "$r"
  echo x >> "$r/bin/a.sh"
  run_hook "$r" 'git commit -m "x"'
  assert_silent "unstaged change without -a"
  run_hook "$r" 'git commit -am "feat: x"'
  [ -n "$OUT" ] || fail "-a should include tracked modifications"
  pass "commit -a counts tracked modifications"
}

test_silent_when_readme_included() {
  local r=$TMP_ROOT/readme
  make_repo "$r"
  echo x >> "$r/bin/a.sh"; echo y >> "$r/README.md"; git -C "$r" add -A
  run_hook "$r" 'git commit -m "feat: x"'
  assert_silent "README staged"
  pass "silent when README.md is in the commit"
}

test_silent_for_docs_merge_and_fixup() {
  local r=$TMP_ROOT/skip
  make_repo "$r"
  echo x >> "$r/bin/a.sh"; git -C "$r" add bin/a.sh
  run_hook "$r" 'git commit -m "docs: words"'; assert_silent "docs subject"
  run_hook "$r" 'git commit -m "docs(x): words"'; assert_silent "docs scoped subject"
  run_hook "$r" 'git commit -m "Merge branch x"'; assert_silent "merge subject"
  run_hook "$r" 'git commit --fixup HEAD'; assert_silent "fixup"
  git -C "$r" reset -q; echo y >> "$r/docs/a.md"; git -C "$r" add docs/a.md
  run_hook "$r" 'git commit -m "feat: notes"' s-docs; assert_silent "docs-only file set"
  pass "silent for docs, merge, fixup, and docs-only commits"
}

test_silent_without_heading_or_commit() {
  local r=$TMP_ROOT/nohead
  make_repo "$r" no
  echo x >> "$r/bin/a.sh"; git -C "$r" add bin/a.sh
  run_hook "$r" 'git commit -m "feat: x"'; assert_silent "no heading"
  make_repo "$TMP_ROOT/other"
  echo x >> "$TMP_ROOT/other/bin/a.sh"; git -C "$TMP_ROOT/other" add bin/a.sh
  run_hook "$TMP_ROOT/other" 'git status'; assert_silent "not a commit"
  run_hook "$TMP_ROOT/other" 'echo git commit'; assert_silent "echoed text"
  pass "silent without the heading and for non-commit commands"
}

test_fails_open() {
  local out rc
  out=$(printf 'not json' | bash "$HOOK" --claude 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] || fail "garbage payload: rc=$rc out=$out"
  out=$(printf '' | bash "$HOOK" --claude 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] || fail "empty payload: rc=$rc"
  run_hook "$TMP_ROOT/does-not-exist" 'git commit -m x'
  assert_silent "missing repository"
  out=$(printf '{"cursor_version":"1","tool_input":{"command":"git commit -m x"}}' | bash "$HOOK" --claude 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] || fail "foreign host: rc=$rc"
  pass "fails open on bad input, missing repo, and foreign hosts"
}

test_tracked_settings_register_hook() {
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]
    | select(.command | contains("/bin/fm-readme-reminder-pretool.sh"))] | length == 1' \
    "$ROOT/.claude/settings.json" >/dev/null || fail "hook not registered once for Bash"
  pass "tracked Claude settings register the hook once for Bash"
}

fm_test_run \
  test_fires_on_user_visible_commit \
  test_commit_all_includes_tracked_modifications \
  test_silent_when_readme_included \
  test_silent_for_docs_merge_and_fixup \
  test_silent_without_heading_or_commit \
  test_fails_open \
  test_tracked_settings_register_hook
