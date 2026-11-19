#!/usr/bin/env bash
# fm-clean.sh - deterministic glue behind the /invoke-cleaner skill.
# The full contract is the usage() text below; run fm-clean.sh --help to read it.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-$FM_ROOT}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
export FM_HOME

SNAPSHOT_BIN="${FM_CLEAN_SNAPSHOT_BIN:-$SCRIPT_DIR/fm-fleet-snapshot.sh}"
TEARDOWN_BIN="${FM_CLEAN_TEARDOWN_BIN:-$SCRIPT_DIR/fm-teardown.sh}"
HOLD_BIN="${FM_CLEAN_HOLD_BIN:-$SCRIPT_DIR/fm-captain-hold.sh}"
TASKS_BIN="${FM_CLEAN_TASKS_BIN:-$SCRIPT_DIR/fm-tasks-axi.sh}"
TMP_ROOT="${FM_CLEAN_TMP_ROOT:-/tmp}"
MIN_AGE_SECS="${FM_CLEAN_MIN_AGE_SECS:-3600}"

usage() {
  cat <<'USAGE'
fm-clean.sh - deterministic glue behind the /invoke-cleaner skill.

Usage:
  fm-clean.sh crew    [--apply] [--record <file>]
  fm-clean.sh backlog [--apply] [--keep <n>] [--record <file>]
  fm-clean.sh tmp     [--apply] [--record <file>]
  fm-clean.sh decide  <task-id> <keep|hold|close|dispatch> [--reason <text>]
                      [--until YYYY-MM-DD] [--words-file <path>] [--apply]
                      [--record <file>]
  fm-clean.sh overview --record <file> [--record <file>...]
  fm-clean.sh --help

Every step except overview is a dry run by default: it prints a plan and
changes nothing. --apply recomputes the same plan from current state and acts
on it. Nothing here finds or deletes by judgment; the skill only chooses what
to ask the captain and how to word the overview.

Output: one record per line, five tab-separated fields:
  <step> <verdict> <subject> <info> <detail>
A field with no value is "-". --record <file> also appends every record to
that file, which `overview` reads back. Verdicts per step:
  crew     teardown | skip                    (plan)
           torn-down | refused | skip         (--apply)
           info = task kind, detail = reason or teardown note
  backlog  done <id> - <title>                (Done rows present now)
           prune - - keep=<n|configured>      (plan)
           archived <id> | kept - - <count>   (--apply)
           open <id> <state[,flags]> <title>  (both modes)
           unavailable - - <reason>           (no readable backlog view)
  tmp      remove | keep  <path> kib=<n>,age_days=<n> <reason>   (plan)
           removed | failed <path> ... <reason>                  (--apply)
  decision <choice> <id> planned|applied|refused <detail>

crew: reads bin/fm-fleet-snapshot.sh --json (the structured fleet view; it
carries bin/fm-crew-state.sh's current state, never a status-log tail) and
plans a teardown only for a task whose current state is done, that is not a
secondmate or a remote task, has no open decision, is not held for the
captain, has no queued or in-flight backlog item blocked by it, and whose
deliverable is recorded as landed: a scout needs its report, a task with a
recorded PR needs this home's own merged evidence for exactly that PR (the
merge poll's notification marker or retirement receipt, read through
bin/fm-pr-lib.sh), and a local-only ship needs its head in the project's local
main. Everything else is a skip with the reason. --apply asks
bin/fm-captain-hold.sh open again and then runs bin/fm-teardown.sh <id>, never
with --force; a refusal is reported as `refused` with teardown's own reason and
the task is left alone. Teardown stays the owner of the landed-work proof.

backlog: lists the Done rows and every open row (queued and in flight, with
held, until, blocked-by and live flags) from the snapshot's backlog view, which
exists for the markdown backend. --apply runs `bin/fm-tasks-axi.sh prune
--state done`, which archives (never deletes) every Done row beyond the
configured recent-Done retention; --keep <n> passes an explicit count instead.
Open rows are only listed: the skill walks them with the captain and applies
each answer through `decide`.

tmp: removes only Firstmate-owned leftovers of tasks this home no longer
records, each a real directory or file owned by the current user and older
than FM_CLEAN_MIN_AGE_SECS (default 3600, so a spawn that is still publishing
its records is never raced):
  - <tmp>/fm-<id>/ per-task temp roots (bin/fm-spawn.sh creates them with a
    gotmp/ child, which this step requires), when no local Firstmate home
    (bin/fm-wake-lib.sh's fm_local_firstmate_state_dirs) records <id>.meta
    and no other home's launch directory for that id exists;
  - <tmp>/fm-<id>+<this home's hash>/ launch directories, when this home
    records no <id>.meta;
  - state/<id>.inbox/ steering inboxes, and the per-task
    .<id>.open-decisions-cursor, .<id>.home-appends and .<id>.home-appends.lock
    records that operational-home-layout names as removed by teardown and safe
    to delete, when this home has neither <id>.meta, <id>.status nor a
    pending <id>.backlog-close.
<tmp> is FM_CLEAN_TMP_ROOT, default /tmp. Nothing under data/, config/,
projects/, or any other state record is ever touched, and the operational
inbox is left to its own retention (bin/fm-operational-input.sh).

decide: applies one captain answer for an open backlog row through its owner.
  keep      records the answer; changes nothing.
  hold      bin/fm-captain-hold.sh hold <id> --reason <text> [--until <date>].
  close     a row held for the captain closes only with the captain's own
            words: bin/fm-captain-hold.sh answer <id> --decision-file <words>.
            Any other row closes with bin/fm-tasks-axi.sh done <id> --note,
            and is refused while state/<id>.meta exists (a live task is
            cleaned up through teardown, not closed under its worker).
  dispatch  records the answer for firstmate's normal dispatch intake; a row
            held for the captain is released first with the captain's words
            through bin/fm-captain-hold.sh answer --release.

overview: summarizes the given record files (torn down, skipped and why, Done
rows archived, decisions, temp space freed) and lists what is still open from
a fresh snapshot. It ends with the line `next: /compact`; the skill tells the
captain to run it and never runs it itself.

Exit status: 0 on success, including a plan with skips or refusals; 1 when a
required read (the snapshot, the backlog, the local home list) fails; 2 on
invalid use. FM_CLEAN_SNAPSHOT_BIN, FM_CLEAN_TEARDOWN_BIN, FM_CLEAN_HOLD_BIN
and FM_CLEAN_TASKS_BIN replace the owner commands for tests.
USAGE
}
die() { printf 'fm-clean: %s\n' "$1" >&2; exit "${2:-1}"; }

case "$MIN_AGE_SECS" in ''|*[!0-9]*) die "FM_CLEAN_MIN_AGE_SECS must be whole seconds" 2 ;; esac

APPLY=0
RECORDS=()
KEEP=
REASON=
UNTIL=
WORDS_FILE=

# One record: five tab-separated fields, tabs and newlines inside a field
# flattened to spaces, empty fields written as "-".
emit() {
  local out='' field i=0 rec
  for field in "$@"; do
    field=$(printf '%s' "$field" | tr '\t\n' '  ')
    [ -n "$field" ] || field=-
    if [ "$i" -eq 0 ]; then out=$field; else out="$out	$field"; fi
    i=$((i + 1))
  done
  printf '%s\n' "$out"
  for rec in ${RECORDS[@]+"${RECORDS[@]}"}; do
    printf '%s\n' "$out" >> "$rec" || die "cannot append to record file $rec"
  done
}

need_jq() { command -v jq >/dev/null 2>&1 || die "jq is required"; }

SNAPSHOT=
load_snapshot() {
  need_jq
  SNAPSHOT=$("$SNAPSHOT_BIN" --json 2>/dev/null) || die "the fleet snapshot failed ($SNAPSHOT_BIN --json)"
  printf '%s' "$SNAPSHOT" | jq -e '.schema == "fm-fleet-snapshot.v1"' >/dev/null 2>&1 \
    || die "the fleet snapshot is not fm-fleet-snapshot.v1"
}

valid_id() {
  case "$1" in
    ''|.*|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
}

# --- crew ---------------------------------------------------------------------

# 0 when this home holds merged evidence for exactly the PR recorded in <id>'s
# meta; bin/fm-pr-lib.sh owns both evidence records and their identity checks.
pr_merged_locally() {  # <id>
  local id=$1 provider host path number
  provider=$FM_PR_META_PROVIDER host=$FM_PR_META_HOST path=$FM_PR_META_PATH number=$FM_PR_META_NUMBER
  fm_pr_poll_merge_already_notified "$STATE" "$id" "$provider" "$host" "$path" "$number" && return 0
  fm_pr_poll_retirement_receipt_valid "$STATE" "$id" \
    && [ "$FM_PR_RETIRE_PROVIDER" = "$provider" ] && [ "$FM_PR_RETIRE_HOST" = "$host" ] \
    && [ "$FM_PR_RETIRE_PATH" = "$path" ] && [ "$FM_PR_RETIRE_NUMBER" = "$number" ]
}

# Sets CREW_VERDICT (teardown|skip) and CREW_REASON for one snapshot row.
crew_classify() {  # <id> <kind> <remote> <state> <decisions> <hold_kind> <backlog_state> <deps> <mode> <report> <worktree> <project>
  local id=$1 kind=$2 remote=$3 state=$4 decisions=$5 hold_kind=$6 backlog_state=$7
  local deps=$8 mode=$9 report=${10} worktree=${11} project=${12} meta head
  CREW_VERDICT=skip
  meta="$STATE/$id.meta"
  if [ "$kind" = secondmate ]; then CREW_REASON="persistent second mate"; return; fi
  if [ "$remote" = 1 ]; then CREW_REASON="remote task"; return; fi
  if [ "$state" != "done" ]; then CREW_REASON="not finished (current state $state)"; return; fi
  if [ "$decisions" != 0 ]; then CREW_REASON="open decision on record"; return; fi
  if [ "$hold_kind" = captain ] && [ "$backlog_state" != "done" ]; then
    CREW_REASON="held for the captain"; return
  fi
  if [ -n "$deps" ]; then CREW_REASON="follow-up $deps depends on it"; return; fi
  if [ "$kind" = scout ]; then
    if [ "$report" != true ]; then CREW_REASON="no scout report yet"; return; fi
    CREW_VERDICT=teardown CREW_REASON="scout report present"; return
  fi
  if fm_pr_metadata_identity_parse "$meta" && [ -n "$FM_PR_META_URL" ]; then
    if pr_merged_locally "$id"; then
      CREW_VERDICT=teardown CREW_REASON="PR merged: $FM_PR_META_URL"; return
    fi
    CREW_REASON="PR not recorded as merged: $FM_PR_META_URL"; return
  fi
  if [ "$mode" = local-only ]; then
    head=$(git -C "$worktree" rev-parse --verify -q HEAD 2>/dev/null) || {
      CREW_REASON="cannot read the local branch head"; return
    }
    if git -C "$project" merge-base --is-ancestor "$head" HEAD 2>/dev/null; then
      CREW_VERDICT=teardown CREW_REASON="local branch is in local main"; return
    fi
    CREW_REASON="local branch not merged into local main"; return
  fi
  CREW_VERDICT=teardown CREW_REASON="finished with no recorded PR; teardown proves landed work"
}

crew_rows() {
  printf '%s' "$SNAPSHOT" | jq -r '
    [ (.backlog.records // [])[]
      | select(.structured and (.state == "queued" or .state == "in_flight")) ] as $open
    | (.tasks // [])[]
    | . as $t
    | [ $open[] | select(any((.unresolved_blocker_ids // [])[]; . == $t.id)) | .id ] as $deps
    | [ .id,
        (.kind // "ship"),
        (if .remote then "1" else "0" end),
        (.current_state.state // "unknown"),
        ((.hints.open_decisions // []) | length | tostring),
        (.backlog.hold_kind // "-"),
        (.backlog.state // "-"),
        (if ($deps | length) > 0 then ($deps | join(",")) else "-" end),
        (.mode // "-"),
        ((.paths.report.present // false) | tostring),
        (.paths.worktree.path // "-"),
        (.project // "-") ]
    | @tsv'
}

crew_teardown() {  # <id> <kind>
  local id=$1 kind=$2 out rc=0 reason open_rc=0
  "$HOLD_BIN" open "$id" >/dev/null 2>&1 || open_rc=$?
  case "$open_rc" in
    0) emit crew skip "$id" "$kind" "held for the captain"; return ;;
    1|3) ;;
    *) emit crew skip "$id" "$kind" "cannot tell whether a captain call is open"; return ;;
  esac
  out=$("$TEARDOWN_BIN" "$id" 2>&1) || rc=$?
  case "$rc" in
    0) emit crew torn-down "$id" "$kind" "cleaned up" ;;
    4) emit crew torn-down "$id" "$kind" "cleaned up, but its pool slot was lost; see teardown output" ;;
    *)
      reason=$(printf '%s\n' "$out" | grep -m1 'REFUSED' || true)
      [ -n "$reason" ] || reason=$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | tail -1)
      emit crew refused "$id" "$kind" "${reason:-teardown exited $rc}"
      ;;
  esac
}

cmd_crew() {
  local id kind remote state decisions hold_kind backlog_state deps mode report worktree project
  # shellcheck source=bin/fm-pr-lib.sh
  . "$SCRIPT_DIR/fm-pr-lib.sh"
  load_snapshot
  while IFS=$'\t' read -r id kind remote state decisions hold_kind backlog_state deps mode report worktree project; do
    [ -n "$id" ] || continue
    [ "$deps" != - ] || deps=
    crew_classify "$id" "$kind" "$remote" "$state" "$decisions" "$hold_kind" "$backlog_state" "$deps" "$mode" "$report" "$worktree" "$project"
    if [ "$CREW_VERDICT" = teardown ] && [ "$APPLY" = 1 ]; then
      crew_teardown "$id" "$kind"
    else
      emit crew "$CREW_VERDICT" "$id" "$kind" "$CREW_REASON"
    fi
  done < <(crew_rows)
}

# --- backlog ------------------------------------------------------------------

backlog_rows() {  # <jq-filter-name: done|open>
  printf '%s' "$SNAPSHOT" | jq -r --arg which "$1" '
    (.backlog.records // [])[]
    | select(.structured)
    | if $which == "done" then select(.state == "done") | [.id, "-", (.title // "-")]
      else select(.state == "queued" or .state == "in_flight")
        | [ .id,
            ([ .state,
               (if .hold_kind then "held=" + .hold_kind else empty end),
               (if .hold_until then "until=" + .hold_until else empty end),
               (if ((.unresolved_blocker_ids // []) | length) > 0
                then "blocked-by=" + ((.unresolved_blocker_ids) | join("+")) else empty end)
             ] | join(",")),
            (.title // "-") ]
      end
    | @tsv'
}

emit_open_rows() {
  local id info title
  while IFS=$'\t' read -r id info title; do
    [ -n "$id" ] || continue
    [ ! -e "$STATE/$id.meta" ] || info="$info,live"
    emit backlog open "$id" "$info" "$title"
  done < <(backlog_rows open)
}

cmd_backlog() {
  local id info title out ids kept
  load_snapshot
  if ! printf '%s' "$SNAPSHOT" | jq -e '.backlog.present == true' >/dev/null 2>&1; then
    emit backlog unavailable - - "no backlog view in the fleet snapshot (no data/backlog.md for this home's backend)"
    return 0
  fi
  if [ "$APPLY" = 0 ]; then
    while IFS=$'\t' read -r id info title; do
      [ -n "$id" ] || continue
      emit backlog "done" "$id" - "$title"
    done < <(backlog_rows "done")
    emit backlog prune - - "keep=${KEEP:-configured}"
  else
    out=$("$TASKS_BIN" prune --state "done" ${KEEP:+--keep "$KEEP"} --json 2>&1) \
      || die "backlog prune failed: $(printf '%s' "$out" | tail -1)"
    ids=$(printf '%s' "$out" | jq -r '.ids[]?' 2>/dev/null) || die "backlog prune printed no JSON result"
    kept=$(printf '%s' "$out" | jq -r '.kept // "-"' 2>/dev/null)
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      emit backlog archived "$id" - -
    done <<EOF
$ids
EOF
    emit backlog kept - - "$kept"
    load_snapshot
  fi
  emit_open_rows
}

# --- tmp ----------------------------------------------------------------------

# This home's launch-directory token. bin/fm-spawn.sh's spawn_launch_home_token
# owns the derivation; this mirrors it so only this home's directories match.
home_token() {
  local root hash
  root=$(cd "$FM_HOME" 2>/dev/null && pwd -P) || root=$FM_HOME
  if command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$root" | shasum -a 256 | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$root" | sha256sum | awk '{print $1}')
  else
    return 1
  fi
  case "$hash" in *[!0-9a-fA-F]*|'') return 1 ;; esac
  printf '%s' "$hash"
}

mtime_epoch() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# Sets TMP_INFO to kib=<n>,age_days=<n>; returns 1 when the path is younger
# than the minimum age or its age cannot be read.
path_facts() {  # <path>
  local now mtime kib age
  now=$(date +%s)
  mtime=$(mtime_epoch "$1") || return 1
  case "$mtime" in ''|*[!0-9]*) return 1 ;; esac
  age=$((now - mtime))
  kib=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
  TMP_INFO="kib=${kib:-0},age_days=$((age / 86400))"
  [ "$age" -ge "$MIN_AGE_SECS" ]
}

owned_real() {  # <path> -> a real (non-link) entry owned by this user
  [ ! -L "$1" ] && [ -e "$1" ] && [ -O "$1" ]
}

LOCAL_STATES=()
load_local_states() {
  # shellcheck source=bin/fm-secondmate-registry-lib.sh
  . "$SCRIPT_DIR/fm-secondmate-registry-lib.sh"
  # shellcheck source=bin/fm-wake-lib.sh
  . "$SCRIPT_DIR/fm-wake-lib.sh"
  fm_local_firstmate_state_dirs "$STATE" || return 1
  LOCAL_STATES=("${FM_LOCAL_FIRSTMATE_STATES[@]}")
}

recorded_anywhere() {  # <id>
  local dir
  for dir in "${LOCAL_STATES[@]}"; do
    [ ! -e "$dir/$1.meta" ] || return 0
  done
  return 1
}

TMP_FREED=0
tmp_candidate() {  # <path> <reason>
  local path=$1 reason=$2 kib
  if ! path_facts "$path"; then
    emit tmp keep "$path" "${TMP_INFO:--}" "younger than ${MIN_AGE_SECS}s or age unreadable"
    return
  fi
  if [ "$APPLY" = 0 ]; then
    emit tmp remove "$path" "$TMP_INFO" "$reason"
  elif rm -rf -- "$path" 2>/dev/null && [ ! -e "$path" ]; then
    kib=${TMP_INFO#kib=}; kib=${kib%%,*}
    TMP_FREED=$((TMP_FREED + kib))
    emit tmp removed "$path" "$TMP_INFO" "$reason"
  else
    emit tmp failed "$path" "$TMP_INFO" "could not remove"
  fi
}

tmp_task_roots() {
  local token=$1 path base id hash sib foreign
  for path in "$TMP_ROOT"/fm-*; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    base=${path##*/}; base=${base#fm-}
    case "$base" in
      *+*)
        id=${base%%+*} hash=${base#*+}
        [ "$hash" = "$token" ] || continue
        valid_id "$id" || continue
        owned_real "$path" && [ -d "$path" ] || { emit tmp keep "$path" - "not a private directory of this user"; continue; }
        if [ -e "$STATE/$id.meta" ]; then emit tmp keep "$path" - "task $id is still recorded"; continue; fi
        tmp_candidate "$path" "launch directory of finished task $id"
        ;;
      *)
        id=$base
        valid_id "$id" || continue
        [ -d "$path/gotmp" ] || continue
        owned_real "$path" && [ -d "$path" ] || { emit tmp keep "$path" - "not a private directory of this user"; continue; }
        if recorded_anywhere "$id"; then emit tmp keep "$path" - "task $id is still recorded"; continue; fi
        foreign=
        for sib in "$TMP_ROOT/fm-$id+"*; do
          [ -e "$sib" ] || continue
          [ "$sib" = "$TMP_ROOT/fm-$id+$token" ] || foreign=1
        done
        if [ -n "$foreign" ]; then emit tmp keep "$path" - "another home launched a task $id"; continue; fi
        tmp_candidate "$path" "temp root of finished task $id"
        ;;
    esac
  done
}

tmp_state_orphans() {
  local path base id
  for path in "$STATE"/*.inbox "$STATE"/.*.open-decisions-cursor "$STATE"/.*.home-appends "$STATE"/.*.home-appends.lock; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    base=${path##*/}
    case "$base" in
      *.inbox) id=${base%.inbox} ;;
      .*.open-decisions-cursor) id=${base#.}; id=${id%.open-decisions-cursor} ;;
      .*.home-appends.lock) id=${base#.}; id=${id%.home-appends.lock} ;;
      .*.home-appends) id=${base#.}; id=${id%.home-appends} ;;
      *) continue ;;
    esac
    valid_id "$id" || continue
    [ ! -e "$STATE/$id.meta" ] && [ ! -e "$STATE/$id.status" ] && [ ! -e "$STATE/$id.backlog-close" ] || continue
    owned_real "$path" || { emit tmp keep "$path" - "not an entry of this user"; continue; }
    tmp_candidate "$path" "leftover record of finished task $id"
  done
}

cmd_tmp() {
  local token
  token=$(home_token) || die "cannot derive this home's launch token"
  load_local_states || die "cannot list the local Firstmate homes: ${FM_LOCAL_FIRSTMATE_ERROR:-unknown}"
  tmp_task_roots "$token"
  tmp_state_orphans
  [ "$APPLY" = 0 ] || emit tmp freed - "kib=$TMP_FREED" "total removed"
}

# --- decide -------------------------------------------------------------------

cmd_decide() {  # <id> <choice>
  local id=$1 choice=$2 open_rc=0 out release
  valid_id "$id" || die "invalid task id: $id" 2
  case "$choice" in keep|hold|close|dispatch) ;; *) die "choice must be keep, hold, close or dispatch" 2 ;; esac
  [ "$choice" != hold ] || [ -n "$REASON" ] || die "hold needs --reason" 2
  [ -z "$WORDS_FILE" ] || [ -s "$WORDS_FILE" ] || die "--words-file must name a non-empty file" 2
  "$HOLD_BIN" open "$id" >/dev/null 2>&1 || open_rc=$?
  case "$choice" in
    keep)
      emit decision keep "$id" "$([ "$APPLY" = 1 ] && echo applied || echo planned)" "${REASON:-kept as is}"
      ;;
    hold)
      if [ "$APPLY" = 0 ]; then emit decision hold "$id" planned "$REASON${UNTIL:+ until $UNTIL}"; return; fi
      if out=$("$HOLD_BIN" hold "$id" --reason "$REASON" ${UNTIL:+--until "$UNTIL"} 2>&1); then
        emit decision hold "$id" applied "$REASON${UNTIL:+ until $UNTIL}"
      else
        emit decision hold "$id" refused "$(printf '%s' "$out" | tail -1)"
      fi
      ;;
    close|dispatch)
      case "$open_rc" in
        0)
          [ -n "$WORDS_FILE" ] || { emit decision "$choice" "$id" refused "held for the captain: needs the captain's own words (--words-file)"; return; }
          if [ "$APPLY" = 0 ]; then emit decision "$choice" "$id" planned "captain's words recorded on the hold"; return; fi
          release=
          [ "$choice" = close ] || release=--release
          if out=$("$HOLD_BIN" answer "$id" --decision-file "$WORDS_FILE" ${release:+"$release"} 2>&1); then
            emit decision "$choice" "$id" applied "captain's words recorded on the hold${REASON:+; $REASON}"
          else
            emit decision "$choice" "$id" refused "$(printf '%s' "$out" | tail -1)"
          fi
          ;;
        1|3)
          if [ "$choice" = dispatch ]; then
            emit decision dispatch "$id" "$([ "$APPLY" = 1 ] && echo applied || echo planned)" "hand to the normal dispatch intake${REASON:+; $REASON}"
            return
          fi
          [ -n "$REASON" ] || die "close needs --reason" 2
          if [ -e "$STATE/$id.meta" ]; then emit decision close "$id" refused "a live task; clean it up through teardown"; return; fi
          if [ "$APPLY" = 0 ]; then emit decision close "$id" planned "$REASON"; return; fi
          if out=$("$TASKS_BIN" "done" "$id" --note "$REASON" 2>&1); then
            emit decision close "$id" applied "$REASON"
          else
            emit decision close "$id" refused "$(printf '%s' "$out" | tail -1)"
          fi
          ;;
        *) emit decision "$choice" "$id" refused "cannot tell whether a captain call is open" ;;
      esac
      ;;
  esac
}

# --- overview -----------------------------------------------------------------

# The section filters are awk programs, so their $N fields must stay unexpanded.
# shellcheck disable=SC2016
cmd_overview() {
  local all freed n
  [ "${#RECORDS[@]}" -gt 0 ] || die "overview needs --record <file>" 2
  all=$(cat "${RECORDS[@]}" 2>/dev/null) || die "cannot read the record files"
  section() {  # <title> <awk-filter> <print-expr>
    local lines
    lines=$(printf '%s\n' "$all" | awk -F'\t' "$2 { print $3 }")
    n=$(printf '%s' "$lines" | grep -c . || true)
    printf '%s[%s]:\n' "$1" "$n"
    [ "$n" = 0 ] || printf '%s\n' "$lines" | sed 's/^/  /'
  }
  printf 'CLEAN OVERVIEW\n'
  section torn_down '$1=="crew" && $2=="torn-down"' '$3 " (" $4 ") " $5'
  section skipped '$1=="crew" && ($2=="skip" || $2=="refused")' '$3 " (" $4 "): " $5'
  section backlog_archived '$1=="backlog" && $2=="archived"' '$3'
  section decisions '$1=="decision"' '$3 ": " $2 " " $4 " - " $5'
  section temp_removed '$1=="tmp" && $2=="removed"' '$3 " (" $4 ")"'
  section temp_failed '$1=="tmp" && $2=="failed"' '$3 ": " $5'
  freed=$(printf '%s\n' "$all" | awk -F'\t' '$1=="tmp" && $2=="removed" { split($4, a, ","); sub("kib=", "", a[1]); s += a[1] } END { print s + 0 }')
  printf 'temp_freed_kib: %s\n' "$freed"
  load_snapshot
  if printf '%s' "$SNAPSHOT" | jq -e '.backlog.present == true' >/dev/null 2>&1; then
    all=$(emit_open_rows)
    section still_open '$1=="backlog" && $2=="open"' '$3 " [" $4 "] " $5'
  else
    printf 'still_open: unavailable (no backlog view)\n'
  fi
  printf 'next: /compact\n'
}

# --- arguments ----------------------------------------------------------------

[ "$#" -gt 0 ] || { usage >&2; exit 2; }
CMD=$1
shift
case "$CMD" in
  -h|--help|help) usage; exit 0 ;;
  crew|backlog|tmp|overview|decide) ;;
  *) usage >&2; exit 2 ;;
esac
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --record) [ "$#" -ge 2 ] || die "--record needs a file" 2; RECORDS+=("$2"); shift ;;
    --keep) [ "$#" -ge 2 ] || die "--keep needs a number" 2; KEEP=$2; shift
      case "$KEEP" in ''|*[!0-9]*) die "--keep must be a whole number" 2 ;; esac ;;
    --reason) [ "$#" -ge 2 ] || die "--reason needs text" 2; REASON=$2; shift ;;
    --until) [ "$#" -ge 2 ] || die "--until needs a date" 2; UNTIL=$2; shift
      case "$UNTIL" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) die "--until must be YYYY-MM-DD" 2 ;; esac ;;
    --words-file) [ "$#" -ge 2 ] || die "--words-file needs a path" 2; WORDS_FILE=$2; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown flag: $1" 2 ;;
    *) POS+=("$1") ;;
  esac
  shift
done

case "$CMD" in
  decide)
    [ "${#POS[@]}" -eq 2 ] || die "usage: fm-clean.sh decide <task-id> <keep|hold|close|dispatch> ..." 2
    cmd_decide "${POS[0]}" "${POS[1]}"
    ;;
  *)
    [ "${#POS[@]}" -eq 0 ] || die "unexpected argument: ${POS[0]}" 2
    "cmd_$CMD"
    ;;
esac
