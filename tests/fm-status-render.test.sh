#!/usr/bin/env bash
# fm-status-render.sh validates strictly, prints nothing for invalid input, and renders exact bytes.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

RENDER="$ROOT/bin/fm-status-render.sh"
TMP_ROOT=$(fm_test_tmproot fm-status-render)

# run_render <json>: stdin run; sets OUT_FILE, ERR_FILE, RC.
run_render() {
  OUT_FILE="$TMP_ROOT/out"
  ERR_FILE="$TMP_ROOT/err"
  RC=0
  printf '%s' "$1" | bash "$RENDER" >"$OUT_FILE" 2>"$ERR_FILE" || RC=$?
}

# expect_output <json> <expected-bytes-with-printf-escapes> <label>
expect_output() {
  run_render "$1"
  expect_code 0 "$RC" "$3"
  printf '%b' "$2" >"$TMP_ROOT/expected"
  cmp -s "$TMP_ROOT/expected" "$OUT_FILE" || fail "$3: output bytes differ"$'\n'"--- expected ---"$'\n'"$(cat "$TMP_ROOT/expected")"$'\n'"--- got ---"$'\n'"$(cat "$OUT_FILE")"
}

expect_invalid() {
  run_render "$1"
  expect_code 1 "$RC" "$3"
  [ ! -s "$OUT_FILE" ] || fail "$3: invalid input must print nothing on stdout, got: $(cat "$OUT_FILE")"
  assert_contains "$(cat "$ERR_FILE")" "$2" "$3"
}

rep() { printf '%*s' "$2" '' | tr ' ' "$1"; }

test_valid_document_renders_exact_bytes_in_tier_order() {
  local pr='https://github.com/example/repo/pull/12?diff=split&w=1#files'
  local json
  json=$(jq -n --arg pr "$pr" '{
    summary: "Two fixes landed, one waits.",
    groups: [
      {title: "Docs", items: [
        {status: "pending", label: "CI run", note: "queued"},
        {status: "finalizing", label: "Text pass", note: "last edits"}]},
      {title: "Deploy", items: [{status: "blocked", label: "Prod rollout", note: "needs credentials"}]},
      {title: "Review", items: [
        {status: "pending", label: "Scan", note: "running"},
        {status: "action", label: "Merge the fix", url: $pr},
        {status: "blocked", label: "Docs site", note: "build is red"}]},
      {title: "Cleanup", items: [{status: "pending", label: "Branch prune", note: "scheduled"}]}]}')
  printf 'Two fixes landed, one waits.\n\nReview\n  🟢 Merge the fix - %s\n  🔴 Docs site: build is red\n  🟠 Scan: running\n\nDeploy\n  🔴 Prod rollout: needs credentials\n\nDocs\n  🔵 Text pass: last edits\n  🟠 CI run: queued\n\nCleanup\n  🟠 Branch prune: scheduled\n' "$pr" >"$TMP_ROOT/expected"
  run_render "$json"
  expect_code 0 "$RC" "mixed document"
  cmp -s "$TMP_ROOT/expected" "$OUT_FILE" || fail "mixed document: output bytes differ"$'\n'"$(cat "$OUT_FILE")"
  [ ! -s "$ERR_FILE" ] || fail "valid input wrote to stderr"
  pass "a valid document renders exact bytes, tiers first, items ordered, URL untouched"
}

test_every_status_renders_and_absent_statuses_leave_no_line() {
  expect_output '{"groups":[{"title":"A","items":[{"status":"finalizing","label":"f","note":"n"},{"status":"blocked","label":"b","note":"n"},{"status":"action","label":"a"}]},{"title":"B","items":[{"status":"pending","label":"p","note":"n"}]}]}' \
    'A\n  🟢 a\n  🔴 b: n\n  🔵 f: n\n\nB\n  🟠 p: n\n' "all four statuses"
  expect_output '{"groups":[{"title":"Only","items":[{"status":"pending","label":"p","note":"n"}]}]}' 'Only\n  🟠 p: n\n' "one status only"
  assert_not_contains "$(cat "$OUT_FILE")" "🟢" "no action line when no action item"
  assert_not_contains "$(cat "$OUT_FILE")" "🔴" "no blocked line when no blocked item"
  assert_not_contains "$(cat "$OUT_FILE")" "🔵" "no finalizing line when no finalizing item"
  pass "each status renders its own format and a missing status leaves no line"
}

test_group_tiers_keep_input_order_inside_a_tier() {
  expect_output '{"groups":[
    {"title":"One","items":[{"status":"pending","label":"p","note":"n"}]},
    {"title":"Two","items":[{"status":"blocked","label":"b","note":"n"}]},
    {"title":"Three","items":[{"status":"action","label":"a"}]},
    {"title":"Four","items":[{"status":"finalizing","label":"f","note":"n"}]},
    {"title":"Five","items":[{"status":"blocked","label":"b","note":"n"}]},
    {"title":"Six","items":[{"status":"pending","label":"p","note":"n"},{"status":"action","label":"a"}]}]}' \
    'Three\n  🟢 a\n\nSix\n  🟢 a\n  🟠 p: n\n\nTwo\n  🔴 b: n\n\nFive\n  🔴 b: n\n\nOne\n  🟠 p: n\n\nFour\n  🔵 f: n\n' \
    "tier order with input order as the tie-break"
  pass "groups order action, blocked, rest and keep input order inside a tier"
}

test_items_keep_input_order_within_a_status() {
  expect_output '{"groups":[{"title":"G","items":[
    {"status":"pending","label":"p1","note":"n"},{"status":"pending","label":"p2","note":"n"},{"status":"action","label":"a"}]}]}' \
    'G\n  🟢 a\n  🟠 p1: n\n  🟠 p2: n\n' "same-status items"
  pass "items of one status keep their input order"
}

test_summary_alone_and_empty_documents() {
  expect_output '{"summary":"All clear.","groups":[]}' 'All clear.\n' "summary only"
  expect_output '{"groups":[]}' '' "empty groups and no summary"
  [ ! -s "$OUT_FILE" ] || fail "empty document must print nothing"
  expect_output '{"groups":[{"title":"Only","items":[{"status":"action","label":"x"}]}]}' 'Only\n  🟢 x\n' "no summary"
  pass "summary-only, empty, and summary-less documents render exactly"
}

test_url_passes_through_exactly_and_works_on_any_status() {
  local url='https://gitlab.example.com:8443/group/proj/-/merge_requests/7?a=1&b=%20x#note_5'
  local json
  json=$(jq -n --arg u "$url" '{groups:[{title:"T",items:[{status:"action",label:"MR",url:$u},{status:"blocked",label:"B",note:"n",url:$u}]}]}')
  printf 'T\n  🟢 MR - %s\n  🔴 B: n - %s\n' "$url" "$url" >"$TMP_ROOT/expected"
  run_render "$json"
  expect_code 0 "$RC" "url document"
  cmp -s "$TMP_ROOT/expected" "$OUT_FILE" || fail "url was rewritten: $(cat "$OUT_FILE")"
  pass "a URL is printed byte for byte on action and non-action lines"
}

test_length_limits_accept_the_maximum_and_reject_one_more() {
  local ok bad
  ok=$(jq -n --arg s "$(rep s 140)" --arg t "$(rep t 50)" --arg l "$(rep l 60)" --arg n "$(rep n 100)" \
    '{summary:$s,groups:[{title:$t,items:[{status:"pending",label:$l,note:$n}]}]}')
  run_render "$ok"
  expect_code 0 "$RC" "documents at every maximum length"
  bad=$(jq -n --arg s "$(rep s 141)" '{summary:$s,groups:[]}')
  expect_invalid "$bad" 'summary: must have at most 140 characters, got 141' "long summary"
  bad=$(jq -n --arg t "$(rep t 51)" '{groups:[{title:$t,items:[{status:"action",label:"a"}]}]}')
  expect_invalid "$bad" 'groups[0].title: must have at most 50 characters, got 51' "long title"
  bad=$(jq -n --arg l "$(rep l 61)" '{groups:[{title:"T",items:[{status:"action",label:$l}]}]}')
  expect_invalid "$bad" 'groups[0].items[0].label: must have at most 60 characters, got 61' "long label"
  bad=$(jq -n --arg n "$(rep n 101)" '{groups:[{title:"T",items:[{status:"pending",label:"l",note:$n}]}]}')
  expect_invalid "$bad" 'groups[0].items[0].note: must have at most 100 characters, got 101' "long note"
  bad=$(jq -n --arg u "https://example.com/$(rep u 290)" '{groups:[{title:"T",items:[{status:"action",label:"a",url:$u}]}]}')
  expect_invalid "$bad" 'groups[0].items[0].url: must have at most 300 characters' "long url"
  pass "limits accept the maximum and reject one character more, naming the field"
}

test_item_and_group_count_limits() {
  expect_invalid '{"groups":[{"title":"T","items":[
    {"status":"action","label":"1"},{"status":"action","label":"2"},{"status":"action","label":"3"},{"status":"action","label":"4"}]}]}' \
    'groups[0].items: must have at most 3 items, got 4' "four items"
  expect_invalid '{"groups":[{"title":"T","items":[]}]}' 'groups[0].items: must not be empty' "empty group"
  expect_invalid "$(jq -n '{groups:[range(0;13) | {title:"T",items:[{status:"action",label:"a"}]}]}')" \
    'groups: must have at most 12 items, got 13' "thirteen groups"
  pass "item and group counts are capped and empty groups are rejected"
}

test_empty_strings_and_edge_whitespace_are_rejected() {
  expect_invalid '{"summary":"","groups":[]}' 'summary: must not be empty' "empty summary"
  expect_invalid '{"groups":[{"title":"","items":[{"status":"action","label":"a"}]}]}' 'groups[0].title: must not be empty' "empty title"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action","label":""}]}]}' 'groups[0].items[0].label: must not be empty' "empty label"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"pending","label":"l","note":""}]}]}' 'groups[0].items[0].note: must not be empty' "empty note"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action","label":"a","url":""}]}]}' 'groups[0].items[0].url: must not be empty' "empty url"
  expect_invalid '{"groups":[{"title":" T","items":[{"status":"action","label":"a"}]}]}' 'groups[0].title: has the wrong form' "leading space"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action","label":"a "}]}]}' 'groups[0].items[0].label: has the wrong form' "trailing space"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action","label":"   "}]}]}' 'groups[0].items[0].label: has the wrong form' "blank label"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action","label":"two\nlines"}]}]}' 'groups[0].items[0].label: has the wrong form' "newline in label"
  expect_invalid '{"summary":"one\ttab","groups":[]}' 'summary: has the wrong form' "tab in summary"
  pass "empty, blank, multi-line, and edge-space strings are rejected with the field named"
}

test_type_enum_and_unknown_field_failures() {
  expect_invalid '[]' 'document: expected object, got array' "array root"
  expect_invalid '"text"' 'document: expected object, got string' "string root"
  expect_invalid '{"groups":"x"}' 'groups: expected array, got string' "groups type"
  expect_invalid '{"summary":5,"groups":[]}' 'summary: expected string, got integer' "summary type"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action","label":7}]}]}' 'groups[0].items[0].label: expected string, got integer' "label type"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"urgent","label":"a"}]}]}' 'groups[0].items[0].status: must be one of "action", "pending", "finalizing", "blocked", got "urgent"' "bad enum"
  expect_invalid '{"groups":[],"extra":1}' 'extra: unknown field (allowed: summary, groups)' "unknown root field"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action","label":"a"}],"x":1}]}' 'groups[0].x: unknown field (allowed: title, items)' "unknown group field"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action","label":"a","emoji":"x"}]}]}' 'groups[0].items[0].emoji: unknown field (allowed: status, label, note, url)' "unknown item field"
  expect_invalid '{"summary":null,"groups":[]}' 'summary: expected string, got null' "null summary"
  pass "wrong types, bad enums, and unknown fields are rejected with the field path"
}

test_required_fields_and_note_rules() {
  expect_invalid '{}' 'groups: required field is missing' "missing groups"
  expect_invalid '{"groups":[{"items":[{"status":"action","label":"a"}]}]}' 'groups[0].title: required field is missing' "missing title"
  expect_invalid '{"groups":[{"title":"T"}]}' 'groups[0].items: required field is missing' "missing items"
  expect_invalid '{"groups":[{"title":"T","items":[{"label":"a"}]}]}' 'groups[0].items[0].status: required field is missing' "missing status"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action"}]}]}' 'groups[0].items[0].label: required field is missing' "missing label"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"pending","label":"l"}]}]}' 'groups[0].items[0].note: required field is missing (pending, finalizing, and blocked lines need a note)' "pending without note"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"blocked","label":"l"}]}]}' 'groups[0].items[0].note: required field is missing' "blocked without note"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"finalizing","label":"l"}]}]}' 'groups[0].items[0].note: required field is missing' "finalizing without note"
  expect_invalid '{"groups":[{"title":"T","items":[{"status":"action","label":"a","note":"n"}]}]}' 'groups[0].items[0].note: not allowed here (an action line shows no note)' "action with note"
  pass "required fields and the per-status note rule are enforced"
}

test_malformed_urls_are_rejected() {
  local u
  for u in 'http://example.com/x' 'ftp://example.com' 'example.com/x' 'https://' 'https:///path' 'https://exa mple.com' \
    'https://example.com/a b' 'https://user:pw@example.com/x' 'https://-bad.example.com' 'https://example.com:99999999' \
    'www.example.com' '/relative/path'; do
    expect_invalid "$(jq -n --arg u "$u" '{groups:[{title:"T",items:[{status:"action",label:"a",url:$u}]}]}')" \
      'groups[0].items[0].url: has the wrong form' "url $u"
  done
  pass "non-https, hostless, credentialed, and whitespace URLs are rejected"
}

test_every_violation_is_reported_and_stdout_stays_empty() {
  run_render '{"groups":[{"title":"","items":[{"status":"nope","label":""},{"status":"pending","label":"l"}]}],"x":1}'
  expect_code 1 "$RC" "several violations"
  [ ! -s "$OUT_FILE" ] || fail "no partial output on invalid input"
  assert_equals 5 "$(wc -l <"$ERR_FILE" | tr -d ' ')" "one stderr line per violation"
  assert_no_regex '^(error: )?$' "$ERR_FILE" "no blank stderr lines"
  while IFS= read -r line; do
    case "$line" in 'error: '*) : ;; *) fail "stderr line without the error prefix: $line" ;; esac
  done <"$ERR_FILE"
  pass "all violations are reported on stderr and nothing reaches stdout"
}

test_json_parse_failures() {
  expect_invalid '{bad' 'input is not valid JSON' "malformed JSON"
  expect_invalid '' 'input is not valid JSON: expected exactly one JSON document, got 0' "empty input"
  expect_invalid '{"groups":[]} {"groups":[]}' 'expected exactly one JSON document, got 2' "two documents"
  expect_invalid '{"groups":[],}' 'input is not valid JSON' "trailing comma"
  pass "malformed, empty, and multiple documents are rejected"
}

test_file_argument_stdin_dash_and_usage() {
  local doc="$TMP_ROOT/doc.json" rc=0 out
  printf '{"groups":[{"title":"T","items":[{"status":"action","label":"a"}]}]}' >"$doc"
  out=$(bash "$RENDER" "$doc") || fail "file argument failed"
  assert_equals $'T\n  🟢 a' "$out" "file argument"
  out=$(bash "$RENDER" - <"$doc") || fail "dash argument failed"
  assert_equals $'T\n  🟢 a' "$out" "dash reads stdin"
  bash "$RENDER" "$TMP_ROOT/missing.json" >/dev/null 2>"$ERR_FILE" || rc=$?
  expect_code 1 "$rc" "missing file"
  assert_contains "$(cat "$ERR_FILE")" "input file not found" "missing file message"
  rc=0
  bash "$RENDER" --bogus >/dev/null 2>"$ERR_FILE" || rc=$?
  expect_code 2 "$rc" "unknown option"
  rc=0
  bash "$RENDER" "$doc" "$doc" >/dev/null 2>"$ERR_FILE" || rc=$?
  expect_code 2 "$rc" "two file arguments"
  bash "$RENDER" --help | grep -q 'fm-status-render.sh - render' || fail "--help prints the header"
  bash "$RENDER" --schema | jq -e '."$id" == "fm-status-render.v1"' >/dev/null || fail "--schema prints the schema"
  pass "file, stdin, dash, --help, --schema, and bad usage behave as documented"
}

fm_test_run \
  test_valid_document_renders_exact_bytes_in_tier_order \
  test_every_status_renders_and_absent_statuses_leave_no_line \
  test_group_tiers_keep_input_order_inside_a_tier \
  test_items_keep_input_order_within_a_status \
  test_summary_alone_and_empty_documents \
  test_url_passes_through_exactly_and_works_on_any_status \
  test_length_limits_accept_the_maximum_and_reject_one_more \
  test_item_and_group_count_limits \
  test_empty_strings_and_edge_whitespace_are_rejected \
  test_type_enum_and_unknown_field_failures \
  test_required_fields_and_note_rules \
  test_malformed_urls_are_rejected \
  test_every_violation_is_reported_and_stdout_stays_empty \
  test_json_parse_failures \
  test_file_argument_stdin_dash_and_usage
