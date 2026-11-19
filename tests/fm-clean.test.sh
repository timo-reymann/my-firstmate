#!/usr/bin/env bash
# fm-clean.sh plans by default and acts only through its owner commands.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }
command -v tasks-axi >/dev/null 2>&1 || { echo "skip: tasks-axi not found"; exit 0; }

CLEAN="$ROOT/bin/fm-clean.sh"
TMP_ROOT=$(fm_test_tmproot fm-clean)
fm_git_identity fmtest fmtest@example.invalid

make_home() {  # <name>
  HOME_DIR="$TMP_ROOT/$1"
  mkdir -p "$HOME_DIR/data" "$HOME_DIR/state" "$HOME_DIR/config" "$HOME_DIR/projects" "$HOME_DIR/fake"
  fm_test_tasks_toml "$HOME_DIR/.tasks.toml"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$HOME_DIR/data/backlog.md"
  LOG="$HOME_DIR/fake/calls.log"
  : > "$LOG"
  cat > "$HOME_DIR/fake/teardown" <<SH
#!/usr/bin/env bash
printf 'teardown %s\n' "\$*" >> "$LOG"
case "\$1" in refuse-*) echo "REFUSED: \$1 has unlanded work" >&2; exit 1 ;; esac
exit 0
SH
  cat > "$HOME_DIR/fake/hold" <<SH
#!/usr/bin/env bash
printf 'hold %s\n' "\$*" >> "$LOG"
if [ "\$1" = open ]; then
  [ -e "$HOME_DIR/fake/held-\$2" ] && exit 0
  exit 1
fi
exit 0
SH
  cat > "$HOME_DIR/fake/snapshot" <<SH
#!/usr/bin/env bash
cat "$HOME_DIR/fake/snapshot.json"
SH
  chmod +x "$HOME_DIR/fake/teardown" "$HOME_DIR/fake/hold" "$HOME_DIR/fake/snapshot"
}

run_clean() {
  local snapshot="$ROOT/bin/fm-fleet-snapshot.sh"
  [ -z "${FAKE_SNAPSHOT:-}" ] || snapshot="$HOME_DIR/fake/snapshot"
  FM_HOME="$HOME_DIR" FM_CREW_STATE_NO_FORGE=1 FM_CLEAN_SNAPSHOT_BIN="$snapshot" \
    FM_CLEAN_TEARDOWN_BIN="$HOME_DIR/fake/teardown" FM_CLEAN_HOLD_BIN="$HOME_DIR/fake/hold" \
    FM_CLEAN_TMP_ROOT="$HOME_DIR/tmp" FM_CLEAN_MIN_AGE_SECS=3600 \
    bash "$CLEAN" "$@"
}

# One snapshot task row; the backlog part lists open records that may block it.
task_json() {  # <id> <kind> <state> [mode] [worktree] [project] [hold_kind] [decisions] [report]
  jq -n --arg id "$1" --arg kind "$2" --arg state "$3" --arg mode "${4:-local-only}" \
    --arg wt "${5:-}" --arg proj "${6:-}" --arg hold "${7:-}" --argjson dec "${8:-0}" \
    --argjson report "${9:-false}" '
    { id: $id, kind: $kind, mode: $mode, remote: null, project: $proj,
      current_state: { state: $state },
      hints: { open_decisions: [range(0; $dec) | {key: "k"}] },
      paths: { worktree: { path: $wt }, report: { present: $report } },
      backlog: (if $hold == "" then { state: "in_flight", hold_kind: null }
                else { state: "in_flight", hold_kind: $hold } end) }'
}

write_snapshot() {  # <tasks-json-array> [backlog-records-json-array]
  jq -n --argjson tasks "$1" --argjson recs "${2:-[]}" \
    '{ schema: "fm-fleet-snapshot.v1", backlog: { present: true, records: $recs }, tasks: $tasks }' \
    > "$HOME_DIR/fake/snapshot.json"
}

# A local-only ship whose worktree is either merged into local main or one
# commit ahead of it; returns the snapshot row.
local_ship() {  # <id> <merged|unmerged>
  local id=$1 proj="$HOME_DIR/projects/$1" wt="$HOME_DIR/wt-$1"
  fm_git_worktree "$proj" "$wt" "fm/$id" >/dev/null 2>&1
  if [ "$2" = unmerged ]; then
    git -C "$wt" commit -q --allow-empty -m "unlanded work"
  fi
  printf 'kind=ship\nmode=local-only\nproject=%s\nworktree=%s\nbranch=fm/%s\n' "$proj" "$wt" "$id" \
    > "$HOME_DIR/state/$id.meta"
  task_json "$id" ship "done" local-only "$wt" "$proj"
}

test_crew_plan_tears_down_only_finished_unblocked_work() {
  local out tasks
  make_home crew-plan
  FAKE_SNAPSHOT=1
  tasks=$(jq -s . <(local_ship landed merged) <(local_ship refuse-unlanded unmerged) \
    <(local_ship held merged) <(local_ship parent merged) \
    <(task_json busy ship working) <(task_json mate secondmate "done") \
    <(task_json asking ship "done" local-only "" "" "" 1) \
    <(task_json scout-done scout "done" no-mistakes "" "" "" 0 true) \
    <(task_json scout-empty scout "done" no-mistakes))
  tasks=$(printf '%s' "$tasks" | jq 'map(if .id == "held" then .backlog.hold_kind = "captain" else . end)')
  write_snapshot "$tasks" '[{"structured":true,"id":"child","state":"queued","unresolved_blocker_ids":["parent"]}]'
  out=$(run_clean crew) || fail "crew plan failed: $out"
  assert_contains "$out" $'crew\tteardown\tlanded\tship' "a merged local-only ship is planned for teardown"
  assert_contains "$out" $'crew\tteardown\tscout-done\tscout' "a scout with its report is planned for teardown"
  assert_contains "$out" $'crew\tskip\trefuse-unlanded\tship\tlocal branch not merged into local main' "unlanded work is skipped"
  assert_contains "$out" $'crew\tskip\theld\tship\theld for the captain' "an open captain hold is skipped"
  assert_contains "$out" $'crew\tskip\tparent\tship\tfollow-up child depends on it' "a task a queued item depends on is skipped"
  assert_contains "$out" $'crew\tskip\tbusy\tship\tnot finished (current state working)' "unfinished work is skipped"
  assert_contains "$out" $'crew\tskip\tmate\tsecondmate\tpersistent second mate' "a secondmate is never torn down"
  assert_contains "$out" $'crew\tskip\tasking\tship\topen decision on record' "an open decision is skipped"
  assert_contains "$out" $'crew\tskip\tscout-empty\tscout\tno scout report yet' "a scout without a report is skipped"
  ! grep -q "^teardown" "$LOG" || fail "the dry run called teardown: $(cat "$LOG")"
  pass "crew dry run plans teardown only for finished, landed, unblocked work"
}

test_crew_apply_runs_teardown_and_reports_refusals() {
  local out tasks rec
  make_home crew-apply
  FAKE_SNAPSHOT=1
  rec="$HOME_DIR/run.tsv"
  tasks=$(jq -s . <(local_ship landed merged) <(local_ship refuse-late merged) <(local_ship held merged))
  touch "$HOME_DIR/fake/held-held"
  write_snapshot "$tasks"
  out=$(run_clean crew --apply --record "$rec") || fail "crew apply failed: $out"
  assert_contains "$out" $'crew\ttorn-down\tlanded\tship' "the landed task was torn down"
  assert_contains "$out" $'crew\trefused\trefuse-late\tship\tREFUSED: refuse-late has unlanded work' "teardown's refusal is reported"
  assert_contains "$out" $'crew\tskip\theld\tship\theld for the captain' "the live hold check skips a held task"
  assert_grep 'teardown landed' "$LOG" "teardown ran for the landed task"
  assert_no_grep 'teardown held' "$LOG" "teardown never ran for the held task"
  assert_no_grep '--force' "$LOG" "teardown is never forced"
  assert_grep $'crew\ttorn-down\tlanded' "$rec" "the record file carries the result"
  pass "crew --apply tears down through fm-teardown.sh and reports refusals as skipped"
}

backlog_fixture() {
  local b="$ROOT/bin/fm-tasks-axi.sh" id
  for id in old-a1 old-b2 old-c3 open-q1 open-f1 held-h1; do
    FM_HOME="$HOME_DIR" "$b" add "$id" "title $id" >/dev/null || fail "could not add $id"
  done
  for id in old-a1 old-b2 old-c3; do
    FM_HOME="$HOME_DIR" "$b" "done" "$id" --no-prune >/dev/null || fail "could not close $id"
  done
  FM_HOME="$HOME_DIR" "$b" start open-f1 >/dev/null || fail "could not start open-f1"
  FM_HOME="$HOME_DIR" "$b" hold held-h1 --reason "captain call" --kind captain >/dev/null || fail "could not hold held-h1"
}

test_backlog_plan_lists_done_and_open_without_changing_it() {
  local out before
  make_home backlog-plan
  unset FAKE_SNAPSHOT
  backlog_fixture
  before=$(cat "$HOME_DIR/data/backlog.md")
  out=$(run_clean backlog) || fail "backlog plan failed: $out"
  assert_contains "$out" $'backlog\tdone\told-a1' "Done rows are listed"
  assert_contains "$out" $'backlog\tprune\t-\t-\tkeep=configured' "the plan names the retention"
  assert_contains "$out" $'backlog\topen\topen-q1\tqueued\ttitle open-q1' "a queued row is listed"
  assert_contains "$out" $'backlog\topen\topen-f1\tin_flight' "an in-flight row is listed"
  assert_contains "$out" $'backlog\topen\theld-h1\tqueued,held=captain' "a captain hold is flagged"
  assert_equals "$before" "$(cat "$HOME_DIR/data/backlog.md")" "the dry run left the backlog unchanged"
  pass "backlog dry run lists Done and open rows and changes nothing"
}

test_backlog_apply_archives_done_rows_through_tasks_axi() {
  local out
  make_home backlog-apply
  unset FAKE_SNAPSHOT
  backlog_fixture
  out=$(run_clean backlog --apply --keep 0) || fail "backlog apply failed: $out"
  assert_contains "$out" $'backlog\tarchived\told-a1' "old-a1 was archived"
  assert_contains "$out" $'backlog\tarchived\told-c3' "old-c3 was archived"
  assert_contains "$out" $'backlog\topen\theld-h1' "open rows are still listed after the prune"
  assert_no_grep 'old-a1' "$HOME_DIR/data/backlog.md" "the Done row left the backlog"
  assert_grep 'old-a1' "$HOME_DIR/data/done-archive.md" "the Done row went to the archive, not to nothing"
  assert_grep 'open-q1' "$HOME_DIR/data/backlog.md" "open rows stay"
  pass "backlog --apply archives Done rows through tasks-axi and keeps open ones"
}

test_backlog_apply_honours_configured_retention() {
  local out
  make_home backlog-keep
  unset FAKE_SNAPSHOT
  sed 's/^done_keep = .*/done_keep = 1/' "$HOME_DIR/.tasks.toml" > "$HOME_DIR/.tasks.toml.new"
  mv "$HOME_DIR/.tasks.toml.new" "$HOME_DIR/.tasks.toml"
  backlog_fixture
  out=$(run_clean backlog --apply) || fail "backlog apply failed: $out"
  assert_contains "$out" $'backlog\tkept\t-\t-\t1' "the configured retention was kept"
  [ "$(printf '%s\n' "$out" | grep -c $'^backlog\tarchived')" = 2 ] || fail "expected two archived rows: $out"
  pass "backlog --apply keeps the configured recent Done rows"
}

home_token() {
  local root
  root=$(cd "$HOME_DIR" && pwd -P)
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$root" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$root" | sha256sum | awk '{print $1}'
  fi
}

tmp_fixture() {
  local t old
  t="$HOME_DIR/tmp"
  TOKEN=$(home_token)
  old=202001010000
  mkdir -p "$t/fm-gone/gotmp" "$t/fm-gone+$TOKEN" "$t/fm-live/gotmp" "$t/fm-shared/gotmp" \
    "$t/fm-shared+0000000000000000000000000000000000000000000000000000000000000000" \
    "$t/fm-young/gotmp" "$t/fm-notask" "$t/fm-other+1111111111111111111111111111111111111111111111111111111111111111" \
    "$t/unrelated" "$HOME_DIR/state/gone.inbox/handled" "$HOME_DIR/state/live.inbox" \
    "$HOME_DIR/state/pending.inbox" "$HOME_DIR/data/gone"
  printf 'x\n' > "$t/fm-gone/gotmp/build.o"
  printf 'report\n' > "$HOME_DIR/data/gone/report.md"
  printf 'cursor\n' > "$HOME_DIR/state/.gone.open-decisions-cursor"
  printf 'kind=ship\n' > "$HOME_DIR/state/live.meta"
  printf 'pending close\n' > "$HOME_DIR/state/pending.backlog-close"
  ln -s "$HOME_DIR/data" "$t/fm-link"
  touch -t "$old" "$t/fm-gone" "$t/fm-gone+$TOKEN" "$t/fm-live" "$t/fm-shared" "$t/fm-notask" "$t/unrelated" \
    "$HOME_DIR/state/gone.inbox" "$HOME_DIR/state/live.inbox" "$HOME_DIR/state/pending.inbox" \
    "$HOME_DIR/state/.gone.open-decisions-cursor"
}

test_tmp_plan_and_apply_touch_only_owned_leftovers() {
  local out t
  make_home tmp
  unset FAKE_SNAPSHOT
  tmp_fixture
  t="$HOME_DIR/tmp"
  out=$(run_clean tmp) || fail "tmp plan failed: $out"
  assert_contains "$out" $'tmp\tremove\t'"$t/fm-gone"$'\tkib=' "an orphan task temp root is planned"
  assert_contains "$out" $'tmp\tremove\t'"$t/fm-gone+$TOKEN" "this home's orphan launch dir is planned"
  assert_contains "$out" $'tmp\tremove\t'"$HOME_DIR/state/gone.inbox" "an orphan steering inbox is planned"
  assert_contains "$out" $'tmp\tremove\t'"$HOME_DIR/state/.gone.open-decisions-cursor" "an orphan decision cursor is planned"
  assert_contains "$out" $'tmp\tkeep\t'"$t/fm-live"$'\t-\ttask live is still recorded' "a recorded task's temp root is kept"
  assert_contains "$out" $'tmp\tkeep\t'"$t/fm-shared"$'\t-\tanother home launched a task shared' "a root another home launched is kept"
  assert_contains "$out" $'tmp\tkeep\t'"$t/fm-young" "a young temp root is kept"
  assert_not_contains "$out" "fm-notask" "a dir without the spawn fingerprint is ignored"
  assert_not_contains "$out" "fm-other+" "another home's launch dir is ignored"
  assert_not_contains "$out" "unrelated" "non-firstmate temp entries are ignored"
  assert_not_contains "$out" "live.inbox" "a live task's inbox is ignored"
  assert_not_contains "$out" "pending.inbox" "an inbox with a pending backlog close is ignored"
  assert_present "$t/fm-gone/gotmp/build.o" "the dry run removed nothing"
  out=$(run_clean tmp --apply) || fail "tmp apply failed: $out"
  assert_absent "$t/fm-gone" "the orphan task temp root was removed"
  assert_absent "$t/fm-gone+$TOKEN" "the orphan launch dir was removed"
  assert_absent "$HOME_DIR/state/gone.inbox" "the orphan inbox was removed"
  assert_absent "$HOME_DIR/state/.gone.open-decisions-cursor" "the orphan cursor was removed"
  assert_contains "$out" $'tmp\tfreed\t-\tkib=' "the apply reports the freed total"
  for keep in "$t/fm-live" "$t/fm-shared" "$t/fm-young" "$t/fm-notask" "$t/unrelated" "$t/fm-link" \
    "$HOME_DIR/state/live.inbox" "$HOME_DIR/state/pending.inbox" "$HOME_DIR/state/live.meta" \
    "$HOME_DIR/data/gone/report.md" "$HOME_DIR/config"; do
    assert_present "$keep" "apply kept $keep"
  done
  pass "tmp cleanup plans by default and removes only owned leftovers of finished tasks"
}

test_decide_applies_answers_through_owners() {
  local out words
  make_home decide
  unset FAKE_SNAPSHOT
  backlog_fixture
  touch "$HOME_DIR/fake/held-held-h1"
  out=$(run_clean decide open-q1 close --reason "obsolete") || fail "close plan failed: $out"
  assert_contains "$out" $'decision\tclose\topen-q1\tplanned\tobsolete' "close is planned by default"
  assert_grep 'open-q1' "$HOME_DIR/data/backlog.md" "the plan did not close the row"
  out=$(run_clean decide open-q1 close --reason "obsolete" --apply) || fail "close failed: $out"
  assert_contains "$out" $'decision\tclose\topen-q1\tapplied' "close is applied"
  FM_HOME="$HOME_DIR" "$ROOT/bin/fm-tasks-axi.sh" show open-q1 | grep -q 'state: done' || fail "open-q1 was not closed"
  out=$(run_clean decide held-h1 close --reason "done" --apply) || fail "held close failed: $out"
  assert_contains "$out" $'decision\tclose\theld-h1\trefused' "a captain call never closes without the captain's words"
  words="$HOME_DIR/words.txt"
  printf 'Drop it.\n' > "$words"
  out=$(run_clean decide held-h1 close --words-file "$words" --apply) || fail "held close with words failed: $out"
  assert_contains "$out" $'decision\tclose\theld-h1\tapplied' "the captain's words close the call"
  assert_grep "hold answer held-h1 --decision-file $words" "$LOG" "the close went through fm-captain-hold.sh answer"
  printf 'kind=ship\n' > "$HOME_DIR/state/open-f1.meta"
  out=$(run_clean decide open-f1 close --reason "x" --apply) || fail "live close failed: $out"
  assert_contains "$out" $'decision\tclose\topen-f1\trefused\ta live task' "a live task is not closed under its worker"
  out=$(run_clean decide open-f1 hold --reason "wait for review" --until 2026-12-01 --apply) || fail "hold failed: $out"
  assert_contains "$out" $'decision\thold\topen-f1\tapplied' "hold is applied"
  assert_grep "hold hold open-f1 --reason wait for review --until 2026-12-01" "$LOG" "hold went through fm-captain-hold.sh"
  pass "decide applies keep, hold and close only through the owner scripts"
}

test_overview_summarizes_records_and_points_to_compact() {
  local out rec
  make_home overview
  unset FAKE_SNAPSHOT
  backlog_fixture
  rec="$HOME_DIR/run.tsv"
  printf '%s\n' $'crew\ttorn-down\tlanded\tship\tcleaned up' \
    $'crew\trefused\tlate\tship\tREFUSED: unlanded' \
    $'crew\tskip\tparent\tship\tfollow-up child depends on it' \
    $'backlog\tarchived\told-a1\t-\t-' \
    $'decision\thold\topen-f1\tapplied\twait' \
    $'tmp\tremoved\t/tmp/fm-gone\tkib=12,age_days=3\ttemp root' \
    $'tmp\tremoved\t/tmp/fm-gone2\tkib=30,age_days=9\ttemp root' > "$rec"
  out=$(run_clean overview --record "$rec") || fail "overview failed: $out"
  assert_contains "$out" "torn_down[1]:" "torn-down count"
  assert_contains "$out" "skipped[2]:" "skips and refusals are counted together"
  assert_contains "$out" "parent (ship): follow-up child depends on it" "a skip keeps its reason"
  assert_contains "$out" "backlog_archived[1]:" "archived count"
  assert_contains "$out" "open-f1: hold applied - wait" "the decision is listed"
  assert_contains "$out" "temp_freed_kib: 42" "freed space is summed"
  assert_contains "$out" "held-h1 [queued,held=captain]" "still-open rows come from the live backlog"
  assert_contains "$out" "next: /compact" "the overview points to /compact"
  pass "overview summarizes the run and ends with the /compact pointer"
}

test_invalid_use_exits_two() {
  local rc=0
  make_home invalid
  run_clean bogus >/dev/null 2>&1 || rc=$?
  expect_code 2 "$rc" "unknown subcommand"
  rc=0
  run_clean decide only-id >/dev/null 2>&1 || rc=$?
  expect_code 2 "$rc" "decide without a choice"
  rc=0
  run_clean decide x hold --apply >/dev/null 2>&1 || rc=$?
  expect_code 2 "$rc" "hold without a reason"
  run_clean --help | grep -q 'fm-clean.sh crew' || fail "--help prints the usage"
  pass "invalid use exits 2 and --help prints the contract"
}

fm_test_run \
  test_crew_plan_tears_down_only_finished_unblocked_work \
  test_crew_apply_runs_teardown_and_reports_refusals \
  test_backlog_plan_lists_done_and_open_without_changing_it \
  test_backlog_apply_archives_done_rows_through_tasks_axi \
  test_backlog_apply_honours_configured_retention \
  test_tmp_plan_and_apply_touch_only_owned_leftovers \
  test_decide_applies_answers_through_owners \
  test_overview_summarizes_records_and_points_to_compact \
  test_invalid_use_exits_two
