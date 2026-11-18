#!/usr/bin/env bash
# Behavior tests for the contrib launchers: the agent choice of contrib/firstmate in dry-run mode,
# and the fleet view contrib/firstmate-herdr puts in the right pane, driven against a fake herdr.
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

# fake_herdr: a herdr that answers the launcher's calls and logs every pane command to $HERDR_LOG.
fake_herdr() {
  cat > "$FAKEBIN/herdr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_LOG"
case "$1 ${2:-}" in
  "status client") echo "protocol: 14" ;;
  "status --json") echo '{"server":{"running":true}}' ;;
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w1"},"root_pane":{"pane_id":"p1"}}}' ;;
  "pane split") echo '{"result":{"pane":{"pane_id":"p2"}}}' ;;
  *) echo '{}' ;;
esac
EOF
  chmod +x "$FAKEBIN/herdr"
}

# herdr_view [VAR=value...]: builds the layout with --no-attach; sets VIEW to the right pane's command.
herdr_view() {
  export HERDR_LOG="$TMP_ROOT/herdr.log"
  : > "$HERDR_LOG"
  OUT=$(env -i HOME="$HOME_DIR" PATH="$FAKEBIN:$BASE_PATH" HERDR_LOG="$HERDR_LOG" "$@" \
    bash "$HERDR_LAUNCHER" --no-attach 2>&1)
  RC=$?
  VIEW=$(sed -n 's/^pane run p2 clear; //p' "$HERDR_LOG")
}

test_herdr_chooses_tui_or_bash() {
  fake_herdr
  herdr_view
  [ "$RC" -eq 0 ] || fail "no uv exit $RC: $OUT"
  assert_contains "$VIEW" "/firstmate-fleet" "no uv falls back to the bash view"
  fm_fake_exit0 "$FAKEBIN" uv
  herdr_view
  [ "$RC" -eq 0 ] || fail "uv exit $RC: $OUT"
  assert_contains "$VIEW" "$FAKEBIN/uv run --script $ROOT/contrib/firstmate-tui" "uv picks the TUI"
  assert_contains "$(sed -n 's/^pane run p1 clear; //p' "$HERDR_LOG")" "/firstmate" "first mate runs on the left"
  herdr_view FIRSTMATE_FLEET_VIEW=bash
  assert_contains "$VIEW" "/firstmate-fleet" "override bash"
  herdr_view FLEET_BIN=/opt/fleet-view
  assert_contains "$VIEW" "/opt/fleet-view" "an explicit FLEET_BIN keeps the bash view"
  herdr_view FLEET_BIN=/opt/fleet-view FIRSTMATE_FLEET_VIEW=tui
  assert_contains "$VIEW" "firstmate-tui" "override tui beats FLEET_BIN"
  herdr_view FIRSTMATE_FLEET_VIEW=gui
  [ "$RC" -ne 0 ] || fail "invalid view accepted"
  assert_contains "$OUT" "FIRSTMATE_FLEET_VIEW must be tui or bash" "invalid view message"
  rm -f "$FAKEBIN/uv"
  herdr_view FIRSTMATE_FLEET_VIEW=tui
  [ "$RC" -ne 0 ] || fail "tui without uv accepted"
  assert_contains "$OUT" "needs uv on PATH" "tui without uv message"
  pass "firstmate-herdr runs the TUI when uv is on PATH, else the bash view, with FIRSTMATE_FLEET_VIEW as override"
}

fm_test_run \
  test_default_is_claude_with_unchanged_command \
  test_env_selects_opencode_and_resume \
  test_file_selects_agent_and_env_wins \
  test_invalid_agent_is_refused \
  test_herdr_chooses_tui_or_bash
