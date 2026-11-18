#!/usr/bin/env bash
# Behavior tests for contrib/firstmate-tui over fake data.
# The uv cases run offline and skip when uv or a cached Textual is missing, so the suite never uses the network.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v python3 >/dev/null 2>&1 || { printf 'skip: python3 absent\n'; exit 0; }

TMP_ROOT=$(fm_test_tmproot fm-contrib-firstmate-tui)
TUI="$ROOT/contrib/firstmate-tui"
export PYTHONDONTWRITEBYTECODE=1

# py <code>: runs Python with the TUI loaded as module `tui`; nonzero on a failed assert.
py() {
  python3 -B - "$TUI" <<EOF
import importlib.machinery, importlib.util, sys, time
loader = importlib.machinery.SourceFileLoader("firstmate_tui", sys.argv[1])
spec = importlib.util.spec_from_loader("firstmate_tui", loader)
tui = importlib.util.module_from_spec(spec)
loader.exec_module(tui)
$1
EOF
}

# make_home <dir>: a fake home with a snapshot fixture; prints the snapshot path.
make_home() {
  local home=$1
  mkdir -p "$home/state" "$home/config" "$home/bin"
  cat > "$home/snapshot.json" <<EOF
{"schema":"fm-fleet-snapshot.v1","fm_home":"$home","roots":{"state":"$home/state","config":"$home/config"},"tasks":[
{"id":"fix-login","kind":"ship","project":"webapp","current_state":{"state":"done"},
 "paths":{"status_log":{"last_event":{"age_seconds":420}}},
 "pr":{"url":"https://github.com/acme/webapp/pull/7"},"endpoint":{"target":"default:p1"},
 "hints":{"pending_decision":false,"blocked_event":false}},
{"id":"audit-cache","kind":"scout","project":"api","current_state":{"state":"working"},
 "paths":{"status_log":{"last_event":{"age_seconds":30}}},"pr":{"url":null},
 "endpoint":{"target":"default:p2"},"hints":{"pending_decision":true,"blocked_event":false}},
{"id":"tidy-docs","kind":"ship","project":"webapp","current_state":{"state":"working"},
 "paths":{"status_log":{"last_event":{"age_seconds":7300}}},"pr":{"url":null},
 "endpoint":{"target":null},"hints":{}},
{"id":"stuck-build","kind":"ship","project":"api","current_state":{"state":"blocked"},
 "pr":{"url":null},"hints":{"pending_decision":false,"blocked_event":true}}]}
EOF
  printf '%s\n' "$home/snapshot.json"
}

# once <home> [args...]: runs --once against the home's fixture; sets OUT and RC.
once() {
  local home=$1
  shift
  OUT=$(FIRSTMATE_DIR="$home" FM_FLEET_SNAPSHOT_CMD="cat '$home/snapshot.json'" python3 -B "$TUI" --once "$@" 2>&1)
  RC=$?
}

test_ledger_parser_tolerates_bad_input() {
  py '
lines = [
  "",
  "not json",
  "[1, 2]",
  "{\"v\":1,\"ts\":10,\"event\":\"task.dispatched\",\"task\":\"a\",\"kind\":\"ship\",\"project\":\"webapp\",\"harness\":\"claude\",\"future\":true}",
  "{\"v\":1,\"ts\":11,\"event\":\"task.status\",\"task\":\"a\",\"state\":\"working\",\"key\":null,\"text\":\" step one\"}",
  "{\"v\":1,\"ts\":11,\"event\":\"task.status\",\"task\":\"a\",\"state\":\"working\",\"key\":null,\"text\":\" step one\"}",
  "{\"v\":1,\"ts\":11,\"event\":\"task.status\",\"task\":\"a\",\"state\":\"working\",\"key\":null,\"text\":\" step two\"}",
  "{\"v\":1,\"ts\":12,\"event\":\"task.someday\",\"task\":\"a\"}",
  "{\"v\":1,\"ts\":\"13\",\"event\":\"task.cleaned_up\",\"task\":\"a\"}",
  "{\"v\":1,\"ts\":14,\"event\":\"task.cleaned_up\"}",
  "{\"v\":1,\"ts\":15,\"event\":\"task.merged\",\"task\":\"a\",\"via\":\"pr\",\"pr\":\"https://github.com/acme/webapp/pull/7\"}",
]
events = tui.parse_ledger_lines(lines)
assert [e["ts"] for e in events] == [10, 11, 11, 15], events
assert tui.format_event(events[0]) == "dispatched ship webapp (claude)"
assert tui.format_event(events[1]) == "working: step one"
assert tui.format_event(events[3]) == "merged https://github.com/acme/webapp/pull/7"
assert tui.format_event({"event": "task.merged", "via": "local"}) == "merged locally"
assert tui.format_event({"event": "task.pr_ready", "pr": "https://x.invalid/pr/1"}) == "PR ready https://x.invalid/pr/1"
assert tui.format_event({"event": "task.cleaned_up"}) == "cleaned up"
' || fail "ledger parser"
  pass "ledger parser skips bad lines and unknown events, and keeps repeated records once"
}

test_ledger_file_partial_tail_and_missing() {
  local ledger="$TMP_ROOT/ledger.jsonl"
  {
    printf '{"v":1,"ts":1,"event":"task.cleaned_up","task":"first"}\n'
    printf '{"v":1,"ts":2,"event":"task.cleaned_up","task":"second"}\n'
    printf '{"v":1,"ts":3,"event":"task.cleaned_up","task":"partial"}'
  } > "$ledger"
  LEDGER="$ledger" py '
import os
events, present = tui.read_ledger(os.environ["LEDGER"])
assert present and [e["task"] for e in events] == ["first", "second"], events
events, present = tui.read_ledger(os.environ["LEDGER"], tail_bytes=os.path.getsize(os.environ["LEDGER"]) - 10)
assert present and [e["task"] for e in events] == ["second"], events
events, present = tui.read_ledger(os.environ["LEDGER"] + ".absent")
assert events == [] and present is False
' || fail "ledger file read"
  pass "ledger read drops a partial last line and a cut first line, and reports a missing file"
}

test_palette_and_symbols() {
  py '
states = ("working", "paused", "decision", "blocked", "done", "pr")
symbols = [tui.STATES[s][0] for s in states]
assert len(set(symbols)) == len(symbols), symbols
assert [tui.kind_info(k)[0] for k in ("ship", "scout", "secondmate")] == ["▲", "◇", "◆"]
assert tui.kind_info("other")[1] == "task"
# Every role has a style at every depth; 16 and 8 colours use ANSI indexes only.
for role in tui.PALETTE:
    for depth in tui.DEPTHS:
        for theme in tui.THEMES:
            style = tui.style_for(role, depth, theme)
            if depth in ("16", "8"):
                assert "#" not in style, (role, depth, style)
assert tui.style_for("decision", "16") == "bold color(11)"
assert tui.style_for("decision", "8") == "bold color(3)"
assert tui.style_for("done", "8") == "dim color(7)"
assert tui.style_for("selected", "16") == "bold color(15) on color(4)"
assert tui.style_for("selected", "8") == "bold color(7) on color(4)"
assert tui.style_for("badge_blocked", "8") == "bold color(7) on color(1)"
assert tui.style_for("working", "truecolor", "light", "panel") == "bold #146c2e on #f0ece2"
assert tui.color_depth({"FIRSTMATE_TUI_COLORS": "8", "COLORTERM": "truecolor"}) == "8"
assert tui.color_depth({"COLORTERM": "truecolor"}) == "truecolor"
assert tui.color_depth({"TERM": "xterm-256color"}) == "256"
assert tui.color_depth({"TERM": "xterm"}, 8) == "8"
assert tui.color_depth({"TERM": "xterm"}) == "16"
assert tui.color_theme({"COLORFGBG": "0;15"}) == "light"
assert tui.color_theme({"COLORFGBG": "15;0"}) == "dark"
assert tui.color_theme({"FIRSTMATE_TUI_THEME": "light"}) == "light"
assert tui.fit("abcdef", 4) == "abc…" and tui.fit("ab", 4) == "ab  "
assert tui.cell_width("日本") == 4
' || fail "palette"
  pass "every state has its own symbol, and the palette maps to 16 and 8 colours and both themes"
}

test_workers_sorting_labels_and_read_marks() {
  local snap
  snap=$(make_home "$TMP_ROOT/parse")
  SNAP="$snap" py '
import os
snap = tui.parse_snapshot(open(os.environ["SNAP"]).read())
assert snap["state_dir"].endswith("/parse/state")
workers = tui.build_workers(snap["tasks"], [], {})
assert [w["id"] for w in workers] == ["audit-cache", "stuck-build", "fix-login", "tidy-docs"], [w["id"] for w in workers]
assert [w["state"] for w in workers] == ["decision", "blocked", "pr", "working"]
assert tui.unread_count(workers) == 3
assert workers[3]["quiet"] and not workers[0]["quiet"]
wide = tui.worker_row(workers[0], 46, False, tui.task_column(workers, 46)).plain()
assert wide.startswith("▌ ? ◇ scout audit-cache") and "decision" in wide and "30s" in wide, wide
narrow = tui.worker_row(workers[0], 36, False, tui.task_column(workers, 36)).plain()
assert "scout" not in narrow and "? ◇ audit-cache" in narrow, narrow
quiet = tui.worker_row(workers[3], 46, True).plain()
assert quiet.startswith("›") and "2h…" in quiet, quiet
assert tui.rail_row(workers[0], 20, False).plain() == "▌?◇ audit-cache     "
# A merged PR is not shown as ready.
merged = [{"event": "task.merged", "task": "fix-login", "ts": 1}]
assert {w["id"]: w["state"] for w in tui.build_workers(snap["tasks"], merged, {})}["fix-login"] == "done"
# A read mark sorts the item after the unread ones until its state, report or PR changes.
read = {"audit-cache": tui.attention_key(workers[0])}
again = tui.build_workers(snap["tasks"], [], read)
assert [w["id"] for w in again][:3] == ["stuck-build", "fix-login", "audit-cache"]
assert tui.unread_count(again) == 2
changed = [dict(t, note="new report") if t["id"] == "audit-cache" else t for t in snap["tasks"]]
assert tui.build_workers(changed, [], read)[0]["unread"]
assert tui.next_needs(again, 0) == 1
assert [tui.format_age(s) for s in (None, 5, 61, 7300, 90000)] == ["-", "5s", "1m", "2h", "1d"]
assert tui.herdr_target("default:w1:p2") == ("w1:p2", [])
assert tui.herdr_target("lab:w1:p2") == ("w1:p2", ["--session", "lab"])
assert tui.herdr_target("") is None
odd = tui.parse_snapshot("{\"tasks\": [7, {\"id\": \"bare\"}]}")
assert odd["tasks"][0]["raw_state"] == "unknown" and odd["tasks"][0]["kind"] == "task"
for bad in ("[]", "not json"):
    try:
        tui.parse_snapshot(bad)
    except ValueError:
        pass
    else:
        raise AssertionError(bad)
' || fail "workers"
  pass "workers sort needs-you first, draw state, kind and age, and a read mark lasts until the item changes"
}

test_shared_selection_file() {
  local dir="$TMP_ROOT/shared"
  mkdir -p "$dir"
  DIR="$dir" py '
import os, json
path = os.path.join(os.environ["DIR"], "firstmate-tui.json")
assert tui.load_shared(path) == {"selected": None, "filter": "all", "read": {}}
for text in ("", "[]", "{\"filter\": \"zoom\", \"selected\": 3, \"read\": [1]}"):
    assert tui.parse_shared(text) == {"selected": None, "filter": "all", "read": {}}, text
tui.save_shared(path, {"selected": "a", "read": {"a": "k", "gone": "k"}}, ["a", "b"])
tui.save_shared(path, {"filter": "task"}, ["a", "b"])
data = json.load(open(path))
assert data == {"v": 1, "selected": "a", "filter": "task", "read": {"a": "k"}}, data
assert sorted(os.listdir(os.environ["DIR"])) == ["firstmate-tui.json"]
' || fail "shared file"
  pass "the shared selection file tolerates bad content, merges changes, drops departed tasks, and leaves no temp file"
}

# fake_screen: the live view reads ANSI lines from this herdr, never from a real one.
fake_screen() {
  cat > "$TMP_ROOT/screen-herdr" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "pane read" ] || exit 1
printf '\033[32m●\033[0m worker line one\n\033[1;33mneeds-decision\033[0m worker line two\n\n'
EOF
  chmod +x "$TMP_ROOT/screen-herdr"
}

# frame <home> <herdr> [args...]: runs --once with a chosen herdr; sets OUT and RC.
frame() {
  local home=$1 herdr=$2
  shift 2
  OUT=$(FIRSTMATE_DIR="$home" FM_FLEET_SNAPSHOT_CMD="cat '$home/snapshot.json'" HERDR_BIN="$herdr" \
    python3 -B "$TUI" --once "$@" 2>&1)
  RC=$?
}

max_width() {
  printf '%s\n' "$1" | python3 -B -c 'import sys; print(max(len(l.rstrip("\n")) for l in sys.stdin))'
}

test_once_activity_frame() {
  local home="$TMP_ROOT/activity" now i
  make_home "$home" >/dev/null
  now=$(date +%s)
  {
    for i in $(seq 1 20); do
      printf '{"v":1,"ts":%s,"event":"task.status","task":"tidy-docs","state":"working","key":null,"text":" step %s"}\n' "$((now - 100 + i))" "$i"
    done
    printf '{"v":1,"ts":%s,"event":"task.status","task":"tidy-docs","state":"working","key":null,"text":" step 20"}\n' "$((now - 80))"
    printf '{"v":1,"ts":%s,"event":"task.pr_ready","task":"fix-login","pr":"https://github.com/acme/webapp/pull/7"}\n' "$now"
    printf '{"v":1,"ts":%s,"event":"task.cleaned_up","task":"half' "$now"
  } > "$home/state/fleet-ledger.jsonl"
  once "$home" --pane activity --width 100
  [ "$RC" -eq 0 ] || fail "--once exit $RC: $OUT"
  assert_equals "10" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "activity box height"
  assert_contains "$(printf '%s\n' "$OUT" | sed -n 1p)" "ACTIVITY · last 8 ─ NEEDS YOU 3" "title and badge"
  assert_contains "$(printf '%s\n' "$OUT" | sed -n 1p)" "l full log" "log hint"
  assert_contains "$(printf '%s\n' "$OUT" | sed -n 2p)" "│▌" "needs-you bar"
  assert_contains "$(printf '%s\n' "$OUT" | sed -n 2p)" "⇡ fix-login" "newest first"
  assert_contains "$OUT" "PR ready https://github.com/acme/webapp/pull/7" "full PR URL"
  assert_contains "$OUT" "● tidy-docs" "working symbol"
  assert_contains "$OUT" "step 14" "the eighth newest event"
  assert_not_contains "$OUT" "step 13" "only the last 8"
  assert_not_contains "$OUT" "half" "partial last line"
  assert_equals "1" "$(printf '%s\n' "$OUT" | grep -c 'step 20')" "a repeated record shows once"
  once "$home" --pane activity --width 80
  assert_equals "80" "$(max_width "$OUT")" "80-column activity"
  assert_contains "$OUT" "NEEDS YOU 3" "80-column badge"
  once "$home" --pane activity --width 50 --height 2
  assert_contains "$(printf '%s\n' "$OUT" | sed -n 1p)" " ACTIVITY · last 8  NEEDS 3" "a low pane falls back to a title row"
  pass "--once activity draws the last 8 events newest first in a box, with the needs-you badge and full lines"
}

test_once_workers_frame_and_fold() {
  local home="$TMP_ROOT/workers"
  make_home "$home" >/dev/null
  fake_screen
  frame "$home" "$TMP_ROOT/screen-herdr" --pane workers --width 48 --height 24
  [ "$RC" -eq 0 ] || fail "--once workers exit $RC: $OUT"
  assert_contains "$OUT" "WORKERS 4 · NEEDS YOU 3" "list title"
  assert_contains "$OUT" "↑↓ move" "move hint"
  assert_contains "$(printf '%s\n' "$OUT" | sed -n 2p)" "› ? ◇ scout audit-cache" "the first row is selected and needs you"
  assert_contains "$OUT" "live · read-only" "live view box"
  assert_contains "$OUT" "● worker line one" "the live view shows the worker screen"
  assert_not_contains "$OUT" $'\033' "the plain frame has no escapes"
  assert_contains "$OUT" "⏎ type into it   o open real tab" "live view footer"
  assert_contains "$(printf '%s\n' "$OUT" | tail -n 1)" "↑↓ select  ⏎ type  o open  l log" "key bar"
  assert_equals "24" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "frame height"
  assert_equals "48" "$(max_width "$OUT")" "frame width"
  frame "$home" "$TMP_ROOT/no-herdr" --pane workers --width 22 --height 18
  [ "$RC" -eq 0 ] || fail "--once rail exit $RC: $OUT"
  assert_contains "$OUT" "TABS 4" "rail title"
  assert_contains "$OUT" "?◇ audit-cache" "compact tab"
  assert_contains "$OUT" "worker view hidden" "the rail hides the live view"
  assert_not_contains "$OUT" "live · read-only" "no live view in the rail"
  assert_equals "22" "$(max_width "$OUT")" "rail width"
  printf '{"selected":"tidy-docs","filter":"all","read":{}}\n' > "$home/state/firstmate-tui.json"
  frame "$home" "$TMP_ROOT/no-herdr" --pane workers --width 48 --height 24
  assert_contains "$OUT" "› ● ▲ ship  tidy-docs" "the shared selection"
  assert_contains "$OUT" "no live view: the worker has no Herdr pane" "a worker without a pane"
  pass "--once workers lists needs-you first over the live view, and folds to a rail at 22 columns"
}

test_input_mode_keys_and_frame() {
  local snap
  snap=$(make_home "$TMP_ROOT/input")
  SNAP="$snap" py '
import os
assert tui.input_for_key("ctrl+right_square_bracket", "\x1d") is None
assert tui.input_for_key("escape", "\x1b") is None
assert tui.escape_resend(10.0, "escape", 10.3) and tui.escape_resend(10.0, "escape", 10.39)
assert not tui.escape_resend(10.0, "escape", 10.5), "too slow"
assert not tui.escape_resend(10.0, "a", 10.1) and not tui.escape_resend(None, "escape", 10.1)
cases = {
    ("a", "a"): ("text", "a"),
    ("A", "A"): ("text", "A"),
    ("space", " "): ("text", " "),
    ("eacute", "é"): ("text", "é"),
    ("q", "q"): ("text", "q"),
    ("enter", "\r"): ("keys", "enter"),
    ("tab", "\t"): ("keys", "tab"),
    ("shift+tab", None): ("keys", "shift+tab"),
    ("backspace", "\x7f"): ("keys", "backspace"),
    ("up", None): ("keys", "up"),
    ("ctrl+up", None): ("keys", "ctrl+up"),
    ("ctrl+c", "\x03"): ("keys", "ctrl+c"),
    ("ctrl+q", "\x11"): ("keys", "ctrl+q"),
    ("ctrl+backslash", "\x1c"): ("keys", "ctrl+\\"),
    ("alt+x", "x"): ("keys", "alt+x"),
    ("f5", None): ("keys", "f5"),
    ("home", None): ("text", "\x1b[H"),
    ("pagedown", None): ("text", "\x1b[6~"),
    ("delete", None): ("text", "\x1b[3~"),
}
for (key, char), want in cases.items():
    assert tui.input_for_key(key, char) == want, (key, tui.input_for_key(key, char))
assert tui.input_commands("hb", "default:w1:p2", "keys", "enter") == [["hb", "pane", "send-keys", "w1:p2", "enter"]]
assert tui.input_commands("hb", "lab:w1:p2", "text", "--session x") == [
    ["hb", "pane", "send-text", "w1:p2", text, "--session", "lab"] for text in ("-", "-", "session x")]
assert tui.input_commands("hb", "default:w1:p2", "text", "-") == [["hb", "pane", "send-text", "w1:p2", "-"]]
assert tui.input_commands("hb", "", "text", "a") == []
assert tui.live_view_shown("workers", 48, 24, 4) and tui.live_view_shown("all", 60, 30, 4)
assert not tui.live_view_shown("workers", 22, 24, 4), "the rail has no live view"
assert not tui.live_view_shown("activity", 100, 24, 4)
snap = tui.parse_snapshot(open(os.environ["SNAP"]).read())
shared = {"selected": None, "filter": "all", "read": {}}
frame = tui.render_pane("workers", 48, 24, snap, [], True, shared, 0, ["prompt>"], "", False, True)
text = tui.plain_frame(frame)
assert "INPUT  audit-cache" in text and "esc leaves" in text, text
assert "typing into audit-cache · esc leaves input" in text, text
assert "live · read-only" not in text, text
assert text.rstrip("\n").split("\n")[-1].startswith(" keys go to the worker  esc leave input"), text
' || fail "input mode"
  pass "input mode sends printable keys as text, named and ctrl keys as herdr keys, leaves on escape and ctrl+], and says INPUT in the live view"
}

test_once_without_ledger_hints_and_stays_read_only() {
  local home="$TMP_ROOT/noledger" before after
  make_home "$home" >/dev/null
  before=$(cd "$home" && find . | LC_ALL=C sort)
  once "$home" --pane activity
  [ "$RC" -eq 0 ] || fail "--once exit $RC: $OUT"
  assert_contains "$OUT" "create config/fleet-ledger" "ledger hint"
  frame "$home" "$TMP_ROOT/no-herdr" --width 60 --height 30
  [ "$RC" -eq 0 ] || fail "--once all exit $RC: $OUT"
  assert_contains "$OUT" "ACTIVITY" "all stacks the activity"
  assert_contains "$OUT" "WORKERS 4" "all stacks the workers"
  after=$(cd "$home" && find . | LC_ALL=C sort)
  assert_equals "$before" "$after" "--once changed the home"
  pass "--once without a ledger shows the hint, and no pane writes anything to the home"
}

test_once_failures_and_help() {
  local home="$TMP_ROOT/fail"
  mkdir -p "$home"
  OUT=$(FIRSTMATE_DIR="$home" FM_FLEET_SNAPSHOT_CMD="exit 3" python3 -B "$TUI" --once 2>&1)
  RC=$?
  [ "$RC" -eq 1 ] || fail "failed snapshot exit $RC"
  assert_contains "$OUT" "snapshot failed" "failed snapshot message"
  OUT=$(FIRSTMATE_DIR="$home" FM_FLEET_SNAPSHOT_CMD="echo nope" python3 -B "$TUI" --once 2>&1)
  RC=$?
  [ "$RC" -eq 1 ] || fail "invalid snapshot exit $RC"
  assert_contains "$OUT" "not valid JSON" "invalid snapshot message"
  OUT=$(python3 -B "$TUI" --help 2>&1)
  RC=$?
  [ "$RC" -eq 0 ] || fail "--help exit $RC"
  assert_contains "$OUT" "--once" "help names --once"
  assert_contains "$OUT" "--interval" "help names --interval"
  assert_contains "$OUT" "FM_FLEET_SNAPSHOT_CMD" "help names the snapshot override"
  assert_contains "$OUT" "--pane NAME" "help names --pane"
  assert_not_contains "$OUT" "zoom" "no zoom"
  OUT=$(python3 -B "$TUI" --once --pane zoom 2>&1)
  [ $? -eq 2 ] || fail "unknown pane accepted: $OUT"
  OUT=$(python3 -B "$TUI" </dev/null 2>&1 | cat)
  assert_contains "$OUT" "use --once" "no-TTY refusal"
  pass "--once reports a failed or invalid snapshot, and --help documents the options"
}

# uv_ready: true when uv can run the script offline from its cache.
uv_ready() {
  command -v uv >/dev/null 2>&1 || return 1
  uv run --offline --quiet --script "$TUI" --help >/dev/null 2>&1
}

test_uv_once_and_headless_app() {
  if ! uv_ready; then
    printf 'ok - uv run --once and the headless app # SKIP uv absent or Textual not cached (the suite stays offline)\n'
    return 0
  fi
  local home="$TMP_ROOT/uv" pilot="$TMP_ROOT/pilot.py" deps herdr="$TMP_ROOT/log-herdr"
  cat > "$herdr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_LOG"
[ "$1 $2" != "pane read" ] || printf 'worker prompt>\n'
EOF
  chmod +x "$herdr"
  make_home "$home" >/dev/null
  OUT=$(FIRSTMATE_DIR="$home" FM_FLEET_SNAPSHOT_CMD="cat '$home/snapshot.json'" HERDR_BIN="$TMP_ROOT/no-herdr" \
    uv run --offline --quiet --script "$TUI" --once --pane workers --width 48 --height 20 2>&1) ||
    fail "uv run --once failed: $OUT"
  assert_contains "$OUT" "WORKERS 4" "uv frame"
  # The app runs headless under the dependencies the script itself declares.
  deps=$(python3 -B -c '
import re, sys
block = re.search(r"^# /// script\n(.*?)^# ///$", open(sys.argv[1]).read(), re.S | re.M).group(1)
print(",".join(re.findall(r"\"([^\"]+)\"", block.split("dependencies", 1)[1])))
' "$TUI") || fail "could not read the script dependencies"
  cat > "$pilot" <<'EOF'
import asyncio, importlib.machinery, importlib.util, json, os, sys
from textual import events
loader = importlib.machinery.SourceFileLoader("firstmate_tui", sys.argv[1])
spec = importlib.util.spec_from_loader("firstmate_tui", loader)
tui = importlib.util.module_from_spec(spec)
loader.exec_module(tui)

async def main():
    app = tui.build_app(os.environ["FIRSTMATE_DIR"], dict(os.environ), 6.0, "workers")
    async with app.run_test(size=(60, 30)) as pilot:
        for _ in range(100):
            await pilot.pause(0.1)
            if app.snapshot is not None:
                break
        shared = os.path.join(os.environ["FIRSTMATE_DIR"], "state", "firstmate-tui.json")
        assert [w["id"] for w in app.rows][:2] == ["audit-cache", "stuck-build"], app.rows
        await pilot.press("down")
        assert app.selected == 1 and json.load(open(shared))["selected"] == "stuck-build"
        await pilot.press("k")
        assert app.selected == 0
        await pilot.press("m")
        assert list(json.load(open(shared))["read"]) == ["audit-cache"]
        assert app.rows[0]["id"] == "stuck-build" and app.rows[app.selected]["id"] == "audit-cache"
        await pilot.press("t")
        assert json.load(open(shared))["filter"] == "task"
        await pilot.press("n")
        assert json.load(open(shared))["filter"] == "needs" and app.rows[app.selected]["unread"]
        await pilot.press("3")
        assert app.selected == 2
        await pilot.press("l")
        assert len(app.screen_stack) == 2
        await pilot.press("escape")
        assert len(app.screen_stack) == 1
        await pilot.press("question_mark")
        assert len(app.screen_stack) == 2
        await pilot.press("escape")
        await pilot.press("o")
        await pilot.press("1")
        assert app.rows[0]["target"] == "", "a worker without a pane"
        await pilot.press("enter")
        assert app.typing is None, "no input mode without a Herdr pane"
        await pilot.press(str([w["id"] for w in app.rows].index("audit-cache") + 1))
        worker = app.rows[app.selected]
        await pilot.press("enter")
        assert app.typing == worker["id"], app.typing
        pane = worker["target"].split(":", 1)[1]
        for key in ("h", "i", "q", "enter", "up", "ctrl+c", "tab", "home"):
            await pilot.press(key)
        app.post_message(events.Paste("pasted -x"))
        await pilot.pause(0.2)
        assert app.typing == worker["id"] and app.rows[app.selected]["id"] == worker["id"] and len(app.screen_stack) == 1
        await pilot.press("escape")
        assert app.typing is None, "one escape leaves at once"
        await pilot.press("escape")
        assert app.typing == worker["id"], "a quick second escape re-enters input mode"
        await pilot.press("ctrl+right_square_bracket")
        assert app.typing is None
        app.escape_left = (worker["id"], worker["target"], tui.time.monotonic() - 1.0)
        await pilot.press("escape")
        assert app.typing is None, "a slow second escape is a plain key"
        want = [("send-text", "hiq"), ("send-keys", "enter"), ("send-keys", "up"),
                ("send-keys", "ctrl+c"), ("send-keys", "tab"), ("send-text", "\x1b[H"),
                ("send-text", "pasted -x"), ("send-keys", "esc")]
        for _ in range(100):
            sends = []
            for line in open(os.environ["HERDR_LOG"]).read().split("\n"):
                parts = line.split(" ", 3)
                if len(parts) == 4 and parts[1] in ("send-keys", "send-text"):
                    assert parts[2] == pane, line
                    if sends and sends[-1][0] == parts[1] == "send-text" and not sends[-1][1].startswith("\x1b"):
                        sends[-1] = (parts[1], sends[-1][1] + parts[3])
                    else:
                        sends.append((parts[1], parts[3]))
            if sends == want:
                break
            await pilot.pause(0.1)
        assert sends == want, sends
        before = app.selected
        await pilot.press("k")
        assert app.selected == max(0, before - 1), "keys move the selection again after input mode"
        await pilot.press("q")
    assert sorted(os.listdir(os.path.join(os.environ["FIRSTMATE_DIR"], "state"))) == ["firstmate-tui.json"]

asyncio.run(main())
EOF
  : > "$TMP_ROOT/herdr.log"
  OUT=$(FIRSTMATE_DIR="$home" FM_FLEET_SNAPSHOT_CMD="cat '$home/snapshot.json'" HERDR_BIN="$herdr" \
    HERDR_LOG="$TMP_ROOT/herdr.log" uv run --offline --quiet --no-project --with "$deps" python -B "$pilot" "$TUI" 2>&1) ||
    fail "headless app failed: $OUT"
  pass "uv runs --once, and the workers app moves, shares the selection, marks read, filters, opens overlays, jumps, and forwards input mode keys in order until escape, and a quick double escape reaches the worker"
}

fm_test_run \
  test_ledger_parser_tolerates_bad_input \
  test_ledger_file_partial_tail_and_missing \
  test_palette_and_symbols \
  test_workers_sorting_labels_and_read_marks \
  test_shared_selection_file \
  test_once_activity_frame \
  test_once_workers_frame_and_fold \
  test_input_mode_keys_and_frame \
  test_once_without_ledger_hints_and_stays_read_only \
  test_once_failures_and_help \
  test_uv_once_and_headless_app
