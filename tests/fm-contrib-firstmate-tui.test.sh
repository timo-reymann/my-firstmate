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

test_snapshot_parsing() {
  local snap
  snap=$(make_home "$TMP_ROOT/parse")
  SNAP="$snap" py '
import os
snap = tui.parse_snapshot(open(os.environ["SNAP"]).read())
ids = [t["id"] for t in snap["tasks"]]
assert ids == ["audit-cache", "stuck-build", "tidy-docs", "fix-login"], ids
assert snap["state_dir"].endswith("/parse/state")
states = {t["id"]: tui.display_state(t) for t in snap["tasks"]}
assert states == {"audit-cache": "needs-decision", "stuck-build": "blocked", "tidy-docs": "working", "fix-login": "done"}, states
assert tui.needs_you(snap["tasks"]) == [
  ("PR ready", "fix-login", "https://github.com/acme/webapp/pull/7"),
  ("decision", "audit-cache", ""),
  ("blocked", "stuck-build", ""),
]
assert [t["id"] for t in tui.filter_tasks(snap["tasks"], "working")] == ["tidy-docs"]
assert len(tui.filter_tasks(snap["tasks"], tui.FILTER_NEEDS_YOU)) == 3
assert tui.filter_choices(snap["tasks"])[:2] == ["all", "needs you"]
assert [tui.format_age(s) for s in (None, 5, 61, 7300, 90000)] == ["-", "5s", "1m", "2h", "1d"]
odd = tui.parse_snapshot("{\"tasks\": [7, {\"id\": \"bare\"}]}")
assert odd["tasks"][0]["state"] == "unknown" and odd["tasks"][0]["kind"] == "task"
for bad in ("[]", "not json"):
    try:
        tui.parse_snapshot(bad)
    except ValueError:
        pass
    else:
        raise AssertionError(bad)
' || fail "snapshot parsing"
  pass "snapshot parsing orders tasks, finds what needs attention, and filters by state"
}

test_once_frame() {
  local home="$TMP_ROOT/frame" now i line
  make_home "$home" >/dev/null
  now=$(date +%s)
  {
    for i in $(seq 1 40); do
      printf '{"v":1,"ts":%s,"event":"task.status","task":"tidy-docs","state":"working","key":null,"text":" step %s"}\n' "$((now - 100 + i))" "$i"
    done
    printf '{"v":1,"ts":%s,"event":"task.pr_ready","task":"fix-login","pr":"https://github.com/acme/webapp/pull/7"}\n' "$now"
  } > "$home/state/fleet-ledger.jsonl"
  once "$home" --width 60
  [ "$RC" -eq 0 ] || fail "--once exit $RC: $OUT"
  assert_contains "$OUT" "firstmate fleet - frame - refreshed" "header"
  assert_contains "$OUT" "! PR ready fix-login" "needs-you PR"
  assert_contains "$OUT" "! decision audit-cache" "needs-you decision"
  assert_contains "$OUT" "! blocked stuck-build" "needs-you blocked"
  assert_contains "$OUT" "TASKS (4)" "task count"
  assert_contains "$OUT" "ACTIVITY (last 30)" "feed size"
  assert_contains "$OUT" "https://github.com/acme/webapp/pull/7" "full PR URL"
  assert_not_contains "$OUT" "step 11"$'\n' "feed keeps only the newest 30"
  [ "$(printf '%s\n' "$OUT" | sed -n '/^ACTIVITY/{n;p;}')" != "" ] || fail "feed lines missing"
  printf '%s\n' "$OUT" | sed -n '/^ACTIVITY/,$p' | sed -n 2,3p | grep -q 'PR ready' || fail "feed is not newest first: $OUT"
  while IFS= read -r line; do
    case "$line" in *https://*) continue ;; esac
    [ "${#line}" -le 60 ] || fail "line wider than 60 columns: $line"
  done <<<"$OUT"
  once "$home" --width 80
  [ "$RC" -eq 0 ] || fail "--once 80 exit $RC"
  while IFS= read -r line; do
    [ "${#line}" -le 80 ] || fail "line wider than 80 columns: $line"
  done <<<"$OUT"
  pass "--once prints the header, needs-you strip, task table and newest 30 events within the width"
}

test_once_without_ledger_hints_and_stays_read_only() {
  local home="$TMP_ROOT/noledger" before after
  make_home "$home" >/dev/null
  before=$(cd "$home" && find . | LC_ALL=C sort)
  once "$home"
  [ "$RC" -eq 0 ] || fail "--once exit $RC: $OUT"
  assert_contains "$OUT" "create config/fleet-ledger" "ledger hint"
  after=$(cd "$home" && find . | LC_ALL=C sort)
  assert_equals "$before" "$after" "--once changed the home"
  pass "--once without a ledger shows the hint and writes nothing to the home"
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
  local home="$TMP_ROOT/uv" pilot="$TMP_ROOT/pilot.py" deps
  make_home "$home" >/dev/null
  OUT=$(FIRSTMATE_DIR="$home" FM_FLEET_SNAPSHOT_CMD="cat '$home/snapshot.json'" uv run --offline --quiet --script "$TUI" --once --width 70 2>&1) ||
    fail "uv run --once failed: $OUT"
  assert_contains "$OUT" "TASKS (4)" "uv frame"
  # The app runs headless under the dependencies the script itself declares.
  deps=$(python3 -B -c '
import re, sys
block = re.search(r"^# /// script\n(.*?)^# ///$", open(sys.argv[1]).read(), re.S | re.M).group(1)
print(",".join(re.findall(r"\"([^\"]+)\"", block.split("dependencies", 1)[1])))
' "$TUI") || fail "could not read the script dependencies"
  cat > "$pilot" <<'EOF'
import asyncio, importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("firstmate_tui", sys.argv[1])
spec = importlib.util.spec_from_loader("firstmate_tui", loader)
tui = importlib.util.module_from_spec(spec)
loader.exec_module(tui)

async def main():
    app = tui.build_app(os.environ["FIRSTMATE_DIR"], dict(os.environ), 6.0)
    async with app.run_test(size=(70, 30)) as pilot:
        for _ in range(100):
            await pilot.pause(0.1)
            if app.snapshot is not None:
                break
        table = app.query_one("DataTable")
        assert table.row_count == 4, table.row_count
        await pilot.press("j")
        assert table.cursor_row == 1, table.cursor_row
        await pilot.press("f")
        assert app.choice == "needs you" and len(app.shown) == 3, (app.choice, len(app.shown))
        await pilot.press("enter")
        await pilot.press("q")

asyncio.run(main())
EOF
  OUT=$(FIRSTMATE_DIR="$home" FM_FLEET_SNAPSHOT_CMD="cat '$home/snapshot.json'" HERDR_BIN="$TMP_ROOT/no-herdr" \
    uv run --offline --quiet --no-project --with "$deps" python -B "$pilot" "$TUI" 2>&1) ||
    fail "headless app failed: $OUT"
  pass "uv runs --once, and the app loads rows, moves, filters and survives a jump outside Herdr"
}

fm_test_run \
  test_ledger_parser_tolerates_bad_input \
  test_ledger_file_partial_tail_and_missing \
  test_snapshot_parsing \
  test_once_frame \
  test_once_without_ledger_hints_and_stays_read_only \
  test_once_failures_and_help \
  test_uv_once_and_headless_app
