#!/usr/bin/env bash
# fm-status-render.sh - render the end-of-turn work list from one JSON document.
#
# Usage:
#   fm-status-render.sh [file]      read the JSON from file, or from stdin when omitted or "-"
#   fm-status-render.sh --schema    print the input schema (bin/fm-status-render.v1.schema.json)
#   fm-status-render.sh --help
#
# The model passes data only; this script owns emojis, order, punctuation, and limits.
# Invalid input prints nothing to stdout: each violation goes to stderr as "error: <field path>: <problem>" and the exit is 1 (2 is bad usage).
#
# Input (object, no other fields):
#   summary  optional one-line outcome summary, printed first and unchanged
#   groups   array (may be empty) of objects, no other fields:
#              title  short one-line text, at most 50 characters
#              items  one to three objects, no other fields (an empty group is rejected):
#                status  action | pending | finalizing | blocked
#                label   short one-line text, at most 60 characters
#                note    short one-line text, at most 100 characters;
#                        required for pending, finalizing, and blocked, refused for action
#                url     optional full https URL, printed exactly as given
#
# Output: the summary line when present, then each group as its title on its own
# line followed by its item lines indented two spaces; one blank line separates
# the summary and every group. Item line formats:
#   action      🟢 <label>
#   pending     🟠 <label>: <note>
#   finalizing  🔵 <label>: <note>
#   blocked     🔴 <label>: <note>
# A url adds " - <url>" to the end of its line.
# Groups print in tiers: groups holding an action item, then groups holding a
# blocked item, then the rest, in input order inside a tier. Inside a group the
# items print action, blocked, finalizing, pending, in input order per status.
# A document with neither a summary nor a group prints nothing and exits 0.
#
# Validation is a small jq checker driven by the schema file; it knows only the keywords the file uses
# (type, enum, const, required, properties, additionalProperties, items, min/max, pattern, allOf, if/then), so extend it before relying on another.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="${FM_STATUS_RENDER_SCHEMA:-$SCRIPT_DIR/fm-status-render.v1.schema.json}"

usage() { sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
die() { printf 'error: %s\n' "$1" >&2; exit "${2:-1}"; }

# Check the document ($doc, one value) against the schema; one message per violation.
# shellcheck disable=SC2016
VALIDATE_JQ='
def jtype:
  if . == null then "null"
  elif type == "number" then (if . == floor then "integer" else "number" end)
  else type end;
def loc($p): if $p == "" then "document" else $p end;
def key($p; $k): if $p == "" then $k else "\($p).\($k)" end;
def istype($t):
  . as $v
  | if $t == "number" then ($v | type) == "number"
    elif $t == "integer" then ($v | type) == "number" and $v == ($v | floor)
    else ($v | type) == $t end;
def hint($s): if ($s | type) == "object" and ($s | has("description")) then " (\($s.description))" else "" end;
def check($s; $p):
  . as $v
  | if $s == true then empty
    elif $s == false then "\(loc($p)): not allowed here"
    elif ($s | has("type")) and ($v | istype($s.type) | not) then
      "\(loc($p)): expected \($s.type), got \($v | jtype)"
    else
      (if ($s | has("const")) and $v != $s.const then
         "\(loc($p)): must be \($s.const | tojson), got \($v | tojson)"
       else empty end),
      (if ($s | has("enum")) and ($s.enum | any(. == $v) | not) then
         "\(loc($p)): must be one of \($s.enum | map(tojson) | join(", ")), got \($v | tojson)"
       else empty end),
      (if ($v | type) == "string" then
         (if ($s | has("minLength")) and ($v | length) < $s.minLength then
            (if $s.minLength == 1 then "\(loc($p)): must not be empty"
             else "\(loc($p)): must have at least \($s.minLength) characters, got \($v | length)" end)
          else empty end),
         (if ($s | has("maxLength")) and ($v | length) > $s.maxLength then
            "\(loc($p)): must have at most \($s.maxLength) characters, got \($v | length)"
          else empty end),
         (if ($s | has("pattern")) and ($v | length) > 0 and ($v | test($s.pattern) | not) then
            "\(loc($p)): has the wrong form\(hint($s))"
          else empty end)
       else empty end),
      (if ($v | type) == "array" then
         (if ($s | has("minItems")) and ($v | length) < $s.minItems then
            (if $s.minItems == 1 then "\(loc($p)): must not be empty"
             else "\(loc($p)): must have at least \($s.minItems) items, got \($v | length)" end)
          else empty end),
         (if ($s | has("maxItems")) and ($v | length) > $s.maxItems then
            "\(loc($p)): must have at most \($s.maxItems) items, got \($v | length)"
          else empty end),
         (if ($s | has("items")) then
            range(0; $v | length) as $i | $v[$i] | check($s.items; "\($p)[\($i)]")
          else empty end)
       else empty end),
      (if ($v | type) == "object" then
         ($s.required // [] | .[] | select(. as $k | $v | has($k) | not)
          | "\(key($p; .)): required field is missing"),
         (if ($s | has("additionalProperties")) and $s.additionalProperties == false then
            ($v | keys_unsorted[] | select(. as $k | ($s.properties // {}) | has($k) | not)
             | "\(key($p; .)): unknown field (allowed: \($s.properties // {} | keys_unsorted | join(", ")))")
          else empty end),
         ($s.properties // {} | to_entries[] | select(.key as $k | $v | has($k))
          | . as $e | $v[$e.key] | check($e.value; key($p; $e.key)))
       else empty end),
      ($s.allOf // [] | .[] | . as $e | $v | check($e; $p) | . + hint($e)),
      (if ($s | has("if")) then
         (if ([$v | check($s.if; $p)] | length) == 0 and ($s | has("then")) then
            $v | check($s.then; $p)
          else empty end)
       else empty end)
    end;
$doc | check($schema[0]; "")
'

# One line per item, in the fixed category order.
# shellcheck disable=SC2016
RENDER_JQ='
def icon: {action: "🟢", pending: "🟠", finalizing: "🔵", blocked: "🔴"}[.];
def line:
  "  \(.status | icon) \(.label)"
  + (if .status == "action" then "" else ": \(.note)" end)
  + (if has("url") then " - \(.url)" else "" end);
def itemrank: {action: 0, blocked: 1, finalizing: 2, pending: 3}[.status];
def tier:
  if any(.items[]; .status == "action") then 0
  elif any(.items[]; .status == "blocked") then 1
  else 2 end;
[ (.summary // empty),
  (.groups | map(. + {tier: tier}) | sort_by(.tier)
   | .[] | ([.title] + (.items | sort_by(itemrank) | map(line))) | join("\n")) ]
| join("\n\n")
'

main() {
  local input="" src out errs doc

  case "${1:-}" in
    -h|--help) usage; return 0 ;;
    --schema) [ $# -eq 1 ] || die "--schema takes no other argument" 2; cat -- "$SCHEMA"; return $? ;;
    -?*) [ "${1:-}" = "-" ] || die "unknown option: $1 (try --help)" 2 ;;
  esac
  [ $# -le 1 ] || die "expected at most one file argument (try --help)" 2
  command -v jq >/dev/null 2>&1 || die "jq is required"
  [ -f "$SCHEMA" ] || die "schema file not found: $SCHEMA"

  src="${1:--}"
  if [ "$src" = "-" ]; then
    input=$(cat) || die "could not read standard input"
  else
    [ -f "$src" ] || die "input file not found: $src"
    input=$(cat -- "$src") || die "could not read input file: $src"
  fi

  # Parse as exactly one JSON value; nothing is printed yet.
  doc=$(printf '%s' "$input" | jq -c -s 'if length == 1 then .[0] else error("expected exactly one JSON document, got \(length)") end' 2>&1) \
    || die "input is not valid JSON: ${doc#jq: error (at <stdin>:0): }"

  errs=$(jq -n -r --slurpfile schema "$SCHEMA" --argjson doc "$doc" "$VALIDATE_JQ" 2>&1) \
    || die "schema validation could not run: $errs"
  if [ -n "$errs" ]; then
    printf '%s\n' "$errs" | sed 's/^/error: /' >&2
    return 1
  fi

  out=$(printf '%s' "$doc" | jq -r "$RENDER_JQ") || die "rendering failed"
  [ -z "$out" ] || printf '%s\n' "$out"
}

main "$@"
