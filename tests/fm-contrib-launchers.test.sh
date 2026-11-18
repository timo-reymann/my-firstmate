#!/usr/bin/env bash
# Behavior tests for the contrib launchers: the agent choice of contrib/firstmate in dry-run mode,
# and the three-pane layout contrib/firstmate-herdr builds, driven against a fake herdr.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-contrib-launchers)
LAUNCHER="$ROOT/contrib/firstmate"
HERDR_LAUNCHER="$ROOT/contrib/firstmate-herdr"
FAKEBIN=$(fm_fakebin "$TMP_ROOT")
# No real uv, opencode or herdr may answer, whatever the host has installed.
BASE_PATH=$(fm_test_base_path_sans "$PATH" uv opencode herdr claude)
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/workspace/firstmate"

# fake_opencode <version> <updated-ms>: an opencode that prints one session list entry.
fake_opencode() {
  cat > "$FAKEBIN/opencode" <<EOF
#!/usr/bin/env bash
case "\$1" in
  --version) echo "opencode v$1" ;;
  session) printf '[\n  {\n    "id": "ses_x",\n    "updated": %s,\n    "directory": "%s"\n  }\n]\n' "$2" "\$PWD" ;;
esac
EOF
  chmod +x "$FAKEBIN/opencode"
}

# launch [VAR=value...] [-- args...]: dry-runs the launcher in a clean environment; sets OUT and RC.
launch() {
  local -a vars=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do vars+=("$1"); shift; done
  [ $# -eq 0 ] || shift
  OUT=$(env -i HOME="$HOME_DIR" PATH="$FAKEBIN:$BASE_PATH" FIRSTMATE_DRY_RUN=1 ${vars[@]+"${vars[@]}"} \
    bash "$LAUNCHER" "$@" 2>&1)
  RC=$?
}

test_default_is_claude_with_unchanged_command() {
  local dir="$HOME_DIR/workspace/firstmate" sessions
  launch
  [ "$RC" -eq 0 ] || fail "default exit $RC: $OUT"
  assert_contains "$OUT" "cd $dir" "default folder"
  assert_contains "$OUT" "CLAUDE_CONFIG_DIR=$HOME_DIR/.claude claude --permission-mode auto --model sonnet Lets\\ start\\ where\\ we\\ left\\ off" "claude fresh start"
  sessions="$HOME_DIR/.claude/projects/$(cd "$dir" && pwd -P | sed 's#[/.]#-#g')"
  mkdir -p "$sessions"
  : > "$sessions/s1.jsonl"
  launch -- --verbose
  assert_contains "$OUT" "claude --permission-mode auto --model sonnet --continue --verbose Lets" "claude resume"
  pass "with no setting the launcher starts claude with its unchanged command"
}

test_env_selects_opencode_and_resume() {
  local now_ms
  now_ms=$(($(date +%s) * 1000))
  fake_opencode 2.1.1 "$now_ms"
  launch FIRSTMATE_AGENT=opencode -- --auto
  [ "$RC" -eq 0 ] || fail "opencode exit $RC: $OUT"
  assert_contains "$OUT" " opencode --standalone --continue --auto --prompt Lets\\ start" "fresh session continues"
  assert_not_contains "$OUT" "claude" "no claude for opencode"
  fake_opencode 2.1.1 $((now_ms - 3 * 3600 * 1000))
  launch FIRSTMATE_AGENT=opencode
  assert_contains "$OUT" " opencode --standalone --prompt Lets\\ start" "stale session starts fresh"
  launch FIRSTMATE_AGENT=opencode FIRSTMATE_MAX_AGE_MIN=600
  assert_contains "$OUT" "--continue" "max age widens freshness"
  fake_opencode 1.18.31 "$now_ms"
  launch FIRSTMATE_AGENT=opencode
  assert_contains "$OUT" " opencode --prompt Lets\\ start" "opencode 1 takes no --standalone"
  rm -f "$FAKEBIN/opencode"
  pass "FIRSTMATE_AGENT=opencode starts opencode, continuing only a fresh OpenCode 2 session"
}

test_file_selects_agent_and_env_wins() {
  local xdg="$TMP_ROOT/xdg"
  mkdir -p "$xdg/firstmate" "$HOME_DIR/.config/firstmate"
  printf '\n   \n  opencode  \nclaude\n' > "$xdg/firstmate/agent"
  launch XDG_CONFIG_HOME="$xdg"
  [ "$RC" -eq 0 ] || fail "file exit $RC: $OUT"
  assert_contains "$OUT" " opencode --prompt" "first non-empty line of the XDG file"
  launch XDG_CONFIG_HOME="$xdg" FIRSTMATE_AGENT=claude
  assert_contains "$OUT" " claude --permission-mode auto" "env beats file"
  printf 'opencode\n' > "$HOME_DIR/.config/firstmate/agent"
  launch
  assert_contains "$OUT" " opencode --prompt" "HOME/.config is the default folder"
  printf '\n\n' > "$HOME_DIR/.config/firstmate/agent"
  launch
  assert_contains "$OUT" " claude --permission-mode auto" "blank file falls back to claude"
  rm -f "$HOME_DIR/.config/firstmate/agent"
  pass "the agent file selects the agent, FIRSTMATE_AGENT overrides it, and a blank file means claude"
}

test_invalid_agent_is_refused() {
  local xdg="$TMP_ROOT/xdg-bad"
  launch FIRSTMATE_AGENT=codex
  [ "$RC" -eq 2 ] || fail "invalid env exit $RC"
  assert_contains "$OUT" "unsupported agent 'codex' (from FIRSTMATE_AGENT); use claude or opencode." "env refusal"
  assert_not_contains "$OUT" "cd " "nothing printed to run"
  mkdir -p "$xdg/firstmate"
  printf 'vim\n' > "$xdg/firstmate/agent"
  launch XDG_CONFIG_HOME="$xdg"
  [ "$RC" -eq 2 ] || fail "invalid file exit $RC"
  assert_contains "$OUT" "unsupported agent 'vim' (from $xdg/firstmate/agent)" "file refusal names the file"
  pass "an unsupported agent is refused with a message naming claude and opencode"
}

# fake_herdr: a herdr that answers the launcher's calls, numbers new panes p2, p3, ..., and logs every call to $HERDR_LOG.
fake_herdr() {
  cat > "$FAKEBIN/herdr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_LOG"
case "$1 ${2:-}" in
  "status client") echo "protocol: 14" ;;
  "status --json") echo '{"server":{"running":true}}' ;;
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w1"},"root_pane":{"pane_id":"p1"}}}' ;;
  "pane split")
    n=$(($(grep -c '^pane split' "$HERDR_LOG") + 1))
    printf '{"result":{"pane":{"pane_id":"p%s"}}}\n' "$n" ;;
  *) echo '{}' ;;
esac
EOF
  chmod +x "$FAKEBIN/herdr"
}

# herdr_layout [VAR=value...] [-- args...]: builds the layout with --no-attach; sets OUT, RC and LOG.
herdr_layout() {
  local -a vars=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do vars+=("$1"); shift; done
  [ $# -eq 0 ] || shift
  export HERDR_LOG="$TMP_ROOT/herdr.log"
  : > "$HERDR_LOG"
  OUT=$(env -i HOME="$HOME_DIR" PATH="$FAKEBIN:$BASE_PATH" HERDR_LOG="$HERDR_LOG" ${vars[@]+"${vars[@]}"} \
    bash "$HERDR_LAUNCHER" --no-attach "$@" 2>&1)
  RC=$?
  LOG=$(cat "$HERDR_LOG")
}

test_herdr_builds_three_panes() {
  local tui="$FAKEBIN/uv run --script $ROOT/contrib/firstmate-tui"
  fake_herdr
  fm_fake_exit0 "$FAKEBIN" uv
  herdr_layout
  [ "$RC" -eq 0 ] || fail "layout exit $RC: $OUT"
  assert_contains "$LOG" "pane split p1 --direction down --ratio 0.28 --no-focus" "activity split"
  assert_contains "$LOG" "pane swap --source-pane p1 --target-pane p2" "activity moves to the top"
  assert_contains "$LOG" "pane split p1 --direction right --ratio 0.6 --no-focus" "workers split"
  assert_contains "$LOG" "pane rename p2 firstmate-activity" "activity label"
  assert_contains "$LOG" "pane rename p3 firstmate-workers" "workers label"
  assert_contains "$(sed -n 's/^pane run p2 clear; //p' "$HERDR_LOG")" "$tui --pane activity" "activity pane"
  assert_contains "$(sed -n 's/^pane run p3 clear; //p' "$HERDR_LOG")" "$tui --pane workers" "workers pane"
  assert_contains "$(sed -n 's/^pane run p1 clear; //p' "$HERDR_LOG")" "$ROOT/contrib/firstmate" "first mate bottom left"
  assert_not_contains "$LOG" "tab rename" "worker tabs keep their labels"
  herdr_layout -- --ratio 0.7 --activity-ratio 0.2
  assert_contains "$LOG" "pane split p1 --direction down --ratio 0.2 --no-focus" "--activity-ratio"
  assert_contains "$LOG" "pane split p1 --direction right --ratio 0.7 --no-focus" "--ratio"
  herdr_layout FM_HERDR_SESSION=lab
  assert_contains "$LOG" "pane split p1 --direction down --ratio 0.28 --no-focus --session lab" "named session"
  OUT=$(bash "$HERDR_LAUNCHER" --help 2>&1)
  assert_contains "$OUT" "--activity-ratio SHARE" "help names --activity-ratio"
  pass "firstmate-herdr puts the activity across the top, the first mate bottom left and the workers bottom right"
}

test_herdr_needs_uv() {
  fake_herdr
  rm -f "$FAKEBIN/uv"
  herdr_layout
  [ "$RC" -ne 0 ] || fail "no uv accepted: $OUT"
  assert_contains "$OUT" "needs uv on PATH" "no uv message"
  assert_contains "$OUT" "https://docs.astral.sh/uv/" "install hint"
  assert_not_contains "$LOG" "pane split" "no layout without uv"
  pass "firstmate-herdr stops with an install hint when uv is missing"
}

fm_test_run \
  test_default_is_claude_with_unchanged_command \
  test_env_selects_opencode_and_resume \
  test_file_selects_agent_and_env_wins \
  test_invalid_agent_is_refused \
  test_herdr_builds_three_panes \
  test_herdr_needs_uv
