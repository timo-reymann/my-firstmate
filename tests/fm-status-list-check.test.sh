#!/usr/bin/env bash
# fm-status-list-check.sh recognises hand-written work lists, and the turn-end guard blocks one per prompt.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

CHECK="$ROOT/bin/fm-status-list-check.sh"
RENDER="$ROOT/bin/fm-status-render.sh"
TMP_ROOT=$(fm_test_tmproot fm-status-list-check)
fm_git_identity fmtest fmtest@example.invalid

# run_check <text>: sets OUT and RC.
run_check() {
  RC=0
  OUT=$(printf '%s\n' "$1" | bash "$CHECK" 2>&1) || RC=$?
}

expect_clean() {
  run_check "$1"
  expect_code 0 "$RC" "$2"
  [ -z "$OUT" ] || fail "$2: clean text printed output: $OUT"
}

expect_flagged() {
  run_check "$1"
  expect_code 1 "$RC" "$2"
  [ -n "$OUT" ] || fail "$2: flagged text named no line"
}

render() { printf '%s' "$1" | bash "$RENDER"; }

FULL_DOC='{"summary":"Two fixes landed, one waits.","groups":[
  {"title":"Review","items":[
    {"status":"pending","label":"Scan","note":"running"},
    {"status":"action","label":"Merge the fix","url":"https://github.com/example/repo/pull/12"},
    {"status":"blocked","label":"Docs site","note":"build is red"}]},
  {"title":"Deploy","items":[{"status":"finalizing","label":"Prod rollout","note":"last edits"}]},
  {"title":"Cleanup","items":[{"status":"pending","label":"Branch prune","note":"scheduled: tonight"}]}]}'

test_genuine_renderer_output_passes_unchanged() {
  local doc out
  out=$(render "$FULL_DOC")
  expect_clean "$out" "full document"
  expect_clean "Done.

$out

Which one first?" "output between prose paragraphs"
  expect_clean "Here is the list:
$out" "output directly after a lead-in line"
  expect_clean "$(render '{"groups":[{"title":"Only","items":[{"status":"action","label":"Ship it"}]}]}')" "single action item"
  expect_clean "$(render '{"summary":"Nothing is running.","groups":[]}')" "summary only"
  for doc in \
    '{"groups":[{"title":"A","items":[{"status":"pending","label":"x","note":"n"},{"status":"pending","label":"y","note":"n"},{"status":"pending","label":"z","note":"n"}]}]}' \
    '{"groups":[{"title":"A","items":[{"status":"blocked","label":"x","note":"n"},{"status":"finalizing","label":"y","note":"n"},{"status":"pending","label":"z","note":"n"}]}]}'; do
    expect_clean "$(render "$doc")" "rendered group $doc"
  done
  pass "genuine renderer output passes, alone or inside prose"
}

test_hand_written_emoji_lists_are_flagged() {
  expect_flagged "Still going:
🟠 Scan: running
🟢 Merge the fix" "bare emoji lines under prose"
  expect_flagged "Review
- 🟢 Merge the fix
- 🟠 Scan: running" "bulleted emoji items"
  expect_flagged "Review
1. 🟢 Merge the fix" "numbered emoji item"
  expect_flagged "Review
    🟢 Merge the fix
    🟠 Scan: running" "four-space indent under a title"
  expect_flagged "Review
 🟢 Merge the fix" "one-space indent"
  expect_flagged "Review
   🟢 Merge the fix" "three-space indent"
  expect_flagged "Review
  🟢  Merge the fix" "double space after the emoji"
  expect_flagged "  🟢 Merge the fix
  🟠 Scan: running" "items without a title"
  expect_flagged "🟢 All done" "a lone status line"
  expect_flagged "Review
  🟠 Scan running" "pending item without a note"
  expect_flagged "Review
  🔴 Docs site" "blocked item without a note"
  expect_flagged "Review
  🟠 Scan: running
  🟢 Merge the fix" "items out of renderer order"
  expect_flagged "Review
  🟢 One
  🟢 Two
  🟢 Three
  🟢 Four" "four items in one group"
  expect_flagged "Review
  🟢 Merge the fix
Footnote line without a gap" "prose glued under the items"
  expect_flagged "Review
  🟢 Merge the fix

Deploy
- 🔴 Rollout: red" "a good group followed by a bad one"
  run_check "Review
  🟢 Merge the fix

Deploy
- 🔴 Rollout: red"
  assert_contains "$OUT" "line 4: Deploy" "bad group is named"
  assert_not_contains "$OUT" "Merge the fix" "good group is not named"
  pass "hand-typed emoji lists are flagged and the offending lines are named"
}

test_titled_still_running_lists_are_flagged() {
  expect_flagged "Still running:
- tests-axi cleanup: waiting on CI
- relay follow-up: queued" "titled bullet list"
  expect_flagged "**In flight**

1. fix the guard
2. update the docs" "bold heading, blank line, numbered list"
  expect_flagged "## Work in progress (3)
* one
* two
* three" "markdown heading with a count"
  expect_flagged "Under way
- one
- two" "plain heading"
  expect_flagged "TODO:
- one
- two" "todo heading"
  run_check "Still running:
- a
- b"
  assert_contains "$OUT" "line 1: Still running:" "heading line is named"
  pass "a still-running heading over a bullet list is flagged"
}

test_ordinary_text_is_not_flagged() {
  expect_clean "" "empty reply"
  expect_clean "Captain, the fix landed and the checks are green." "plain prose"
  expect_clean "The status is 🟢 now, and the other 🔴 went away." "emoji inside a sentence"
  expect_clean "Still running: the build, which should finish soon." "heading words inside a sentence"
  expect_clean "Still running:

The build is slow today." "heading followed by prose"
  expect_clean "Still running:
- only one thing" "heading with a single bullet"
  expect_clean "In progress
This line is prose." "heading followed by a plain line"
  expect_clean "Options:
- merge it
- wait a day
- close it" "an ordinary bullet list"
  expect_clean "Steps to reproduce:
1. open the page
2. press the button" "a numbered how-to"
  expect_clean "Review
  2 files changed" "indented prose"
  pass "ordinary prose, plain bullet lists, and inline emoji are not flagged"
}

test_code_quotes_and_worker_output_are_not_flagged() {
  local fence='```'
  expect_clean "The worker printed:

$fence
Review
- 🟢 Merge the fix
- 🟠 Scan: running
Still running:
- one
- two
$fence" "backtick fence"
  expect_clean "~~~
🟢 Merge the fix
~~~" "tilde fence"
  expect_clean "$fence text
🟢 Merge the fix
$fence

Done." "fence with an info string, then prose"
  expect_clean "> Review
> - 🟢 Merge the fix
>
> Still running:
> - one
> - two" "blockquote"
  expect_clean "    Review
    - 🟢 Merge the fix
    - 🟠 Scan: running" "indented code block"
  expect_flagged "$fence
fine
$fence

- 🟢 Merge the fix" "a list after a closed fence is still read"
  expect_clean "$fence
🟢 unterminated fence stays code" "unterminated fence"
  pass "fenced code, blockquotes, and indented code are skipped; text after a closed fence is read again"
}

test_check_usage() {
  local rc=0 out
  out=$(bash "$CHECK" --help 2>&1) || rc=$?
  expect_code 0 "$rc" "--help"
  assert_contains "$out" "fm-status-list-check.sh" "--help names the script"
  rc=0
  bash "$CHECK" --bogus >/dev/null 2>&1 || rc=$?
  expect_code 2 "$rc" "unknown option"
  rc=0
  bash "$CHECK" "$TMP_ROOT/missing.txt" >/dev/null 2>&1 || rc=$?
  expect_code 2 "$rc" "missing file"
  rc=0
  bash "$CHECK" a b >/dev/null 2>&1 || rc=$?
  expect_code 2 "$rc" "two arguments"
  printf 'Review\n- 🟢 x\n' > "$TMP_ROOT/list.txt"
  rc=0
  bash "$CHECK" "$TMP_ROOT/list.txt" >/dev/null 2>&1 || rc=$?
  expect_code 1 "$rc" "file argument with a hand-written list"
  rc=0
  printf 'Review\n- 🟢 x\n' | bash "$CHECK" - >/dev/null 2>&1 || rc=$?
  expect_code 1 "$rc" "dash reads stdin"
  pass "--help, bad usage, file argument, and stdin behave as documented"
}

# --- guard wiring -------------------------------------------------------------

# make_home <dir>: a primary-shaped checkout whose guard finds no supervision need, so only the list check can block.
make_home() {
  local dir=$1
  mkdir -p "$dir/state" "$dir/docs"
  git init -q "$dir"
  git -C "$dir" commit -q --allow-empty -m init
  : > "$dir/AGENTS.md"
  cp -R "$ROOT/bin" "$dir/bin"
  cp -R "$ROOT/docs/supervision-protocols" "$dir/docs/supervision-protocols"
  printf '%s\n' "$dir"
}

# payload <message> [prompt_id] [stop_hook_active] [session_id]
payload() {
  jq -cn --arg m "$1" --arg p "${2:-}" --argjson a "${3:-false}" --arg s "${4:-sess-1}" \
    '{session_id: $s, hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: $m}
     + (if $p == "" then {} else {prompt_id: $p} end)'
}

# run_guard <home> <mode flag or ""> <payload>: sets GUARD_RC, GUARD_OUT (stdout) and GUARD_ERR (stderr).
run_guard() {
  local home=$1 flag=$2 body=$3
  GUARD_RC=0
  GUARD_OUT=$(printf '%s' "$body" | FM_HOME="$home" CLAUDECODE=1 bash "$home/bin/fm-turnend-guard.sh" ${flag:+"$flag"} 2>"$TMP_ROOT/guard.err") || GUARD_RC=$?
  GUARD_ERR=$(cat "$TMP_ROOT/guard.err")
}

HAND_LIST=$'Status:\n- 🟢 Merge the fix\n- 🟠 Scan: running'

test_guard_blocks_once_per_prompt_in_claude_mode() {
  local home
  home=$(make_home "$TMP_ROOT/claude-loop")
  run_guard "$home" --claude "$(payload "$HAND_LIST" p1)"
  expect_code 2 "$GUARD_RC" "first hand-written list blocks"
  assert_contains "$GUARD_ERR" "hand-written work list" "block names the problem"
  assert_contains "$GUARD_ERR" "- 🟢 Merge the fix" "block quotes the offending line"
  assert_contains "$GUARD_ERR" "$home/bin/fm-status-render.sh" "block points at the renderer"
  assert_contains "$GUARD_ERR" "fm-status-render.sh --schema" "block points at the schema"
  run_guard "$home" --claude "$(payload "$HAND_LIST" p1 true)"
  expect_code 0 "$GUARD_RC" "retry in the same prompt is let through"
  run_guard "$home" --claude "$(payload "$HAND_LIST" p1 false)"
  expect_code 0 "$GUARD_RC" "same prompt stays through even without stop_hook_active"
  run_guard "$home" --claude "$(payload "$HAND_LIST" p2)"
  expect_code 2 "$GUARD_RC" "a new prompt blocks again"
  run_guard "$home" --claude "$(payload "$HAND_LIST" p3 true)"
  expect_code 0 "$GUARD_RC" "an active stop right after a block is the retry even under a new prompt id"
  pass "claude mode blocks a hand-written list once per prompt and lets the retry through"
}

test_guard_loop_guard_without_prompt_id_and_across_sessions() {
  local home
  home=$(make_home "$TMP_ROOT/claude-noprompt")
  run_guard "$home" --claude "$(payload "$HAND_LIST")"
  expect_code 2 "$GUARD_RC" "no prompt id: first block"
  run_guard "$home" --claude "$(payload "$HAND_LIST" "" true)"
  expect_code 0 "$GUARD_RC" "no prompt id: active retry passes"
  run_guard "$home" --claude "$(payload "$HAND_LIST" p1 false other-session)"
  expect_code 2 "$GUARD_RC" "another session is judged on its own"
  run_guard "$home" --claude "$(payload "$HAND_LIST" "" true third-session)"
  expect_code 0 "$GUARD_RC" "an active stop with no marker for its session and no prompt id is let through"
  rm -f "$home/state/.status-list-guard"
  chmod 500 "$home/state"
  run_guard "$home" --claude "$(payload "$HAND_LIST" fresh)"
  chmod 700 "$home/state"
  if [ "$(id -u)" -ne 0 ]; then
    expect_code 0 "$GUARD_RC" "an unwritable marker never blocks"
  fi
  pass "the loop guard holds without a prompt id, per session, and when the marker cannot be written"
}

test_guard_passes_rendered_and_ordinary_replies() {
  local home out
  home=$(make_home "$TMP_ROOT/claude-clean")
  out=$(render "$FULL_DOC")
  run_guard "$home" --claude "$(payload "$out" c1)"
  expect_code 0 "$GUARD_RC" "genuine renderer output"
  [ -z "$GUARD_ERR" ] || fail "genuine output wrote stderr: $GUARD_ERR"
  run_guard "$home" --claude "$(payload 'The fix landed.' c2)"
  expect_code 0 "$GUARD_RC" "ordinary prose"
  run_guard "$home" --claude "$(payload $'Output:\n```\n- 🟢 x\n```' c3)"
  expect_code 0 "$GUARD_RC" "fenced worker output"
  run_guard "$home" --claude '{"session_id":"s","stop_hook_active":false}'
  expect_code 0 "$GUARD_RC" "payload without a last message"
  run_guard "$home" --claude "$(jq -cn '{session_id:"s",last_assistant_message:["x"]}')"
  expect_code 0 "$GUARD_RC" "non-string last message"
  [ ! -e "$home/state/.status-list-guard" ] || fail "a clean reply wrote a block marker"
  pass "rendered output, prose, fenced output, and missing or odd messages pass without a marker"
}

test_guard_default_mode_honours_stop_hook_active() {
  local home
  home=$(make_home "$TMP_ROOT/default-mode")
  run_guard "$home" "" "$(payload "$HAND_LIST" "" false)"
  expect_code 2 "$GUARD_RC" "default mode blocks the first stop"
  assert_contains "$GUARD_ERR" "fm-status-render.sh" "default mode names the renderer"
  run_guard "$home" "" "$(payload "$HAND_LIST" "" true)"
  expect_code 0 "$GUARD_RC" "default mode lets the stop after a block finish"
  pass "the default (codex-shaped) mode blocks once and lets the active stop through"
}

test_guard_scope_secondmate_and_other_modes_stay_silent() {
  local home sm
  sm=$(make_home "$TMP_ROOT/secondmate")
  printf 'sm-test-1\n' > "$sm/.fm-secondmate-home"
  run_guard "$sm" --claude "$(payload "$HAND_LIST" s1)"
  expect_code 0 "$GUARD_RC" "secondmate home"
  [ -z "$GUARD_ERR" ] || fail "secondmate home wrote stderr: $GUARD_ERR"
  home=$(make_home "$TMP_ROOT/other-modes")
  run_guard "$home" --agy "$(payload "$HAND_LIST" a1)"
  expect_code 0 "$GUARD_RC" "agy mode"
  [ "$GUARD_OUT" = "{}" ] || fail "agy mode must answer {}, got: $GUARD_OUT"
  run_guard "$home" --cursor "$(jq -cn --arg m "$HAND_LIST" '{cursor_version:"1",session_id:"s",last_assistant_message:$m}')"
  expect_code 0 "$GUARD_RC" "cursor mode"
  rm -rf "$TMP_ROOT/not-primary"
  mkdir -p "$TMP_ROOT/not-primary/state"
  cp -R "$ROOT/bin" "$TMP_ROOT/not-primary/bin"
  run_guard "$TMP_ROOT/not-primary" --claude "$(payload "$HAND_LIST" n1)"
  expect_code 0 "$GUARD_RC" "a directory that is not a primary checkout"
  pass "secondmate homes, agy, cursor, and non-primary directories are not checked"
}

test_guard_without_the_checker_lets_the_stop_through() {
  local home
  home=$(make_home "$TMP_ROOT/no-checker")
  rm -f "$home/bin/fm-status-list-check.sh"
  run_guard "$home" --claude "$(payload "$HAND_LIST" m1)"
  expect_code 0 "$GUARD_RC" "missing checker script"
  pass "a missing checker lets the stop through"
}

fm_test_run \
  test_genuine_renderer_output_passes_unchanged \
  test_hand_written_emoji_lists_are_flagged \
  test_titled_still_running_lists_are_flagged \
  test_ordinary_text_is_not_flagged \
  test_code_quotes_and_worker_output_are_not_flagged \
  test_check_usage \
  test_guard_blocks_once_per_prompt_in_claude_mode \
  test_guard_loop_guard_without_prompt_id_and_across_sessions \
  test_guard_passes_rendered_and_ordinary_replies \
  test_guard_default_mode_honours_stop_hook_active \
  test_guard_scope_secondmate_and_other_modes_stay_silent \
  test_guard_without_the_checker_lets_the_stop_through
