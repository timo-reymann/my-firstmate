#!/usr/bin/env bash
# board.css badge glyphs must match the chat emoji in bin/fm-status-render.sh, except action (charcoal triangle, never green).
# The Bearings board template must carry the same stylesheet.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }
command -v perl >/dev/null 2>&1 || { echo "skip: perl not found"; exit 0; }

RENDER="$ROOT/bin/fm-status-render.sh"
CSS="$ROOT/.agents/skills/board-design/assets/board.css"
TEMPLATE="$ROOT/.agents/skills/bearings/assets/board-template.html"
TMP_ROOT=$(fm_test_tmproot fm-board-design-parity)

chat_emoji() {
  jq -n --arg status "$1" '{groups: [{title: "Probe", items: [
      {status: $status, label: "x"} + (if $status == "action" then {} else {note: "y"} end)]}]}' \
    | bash "$RENDER" | sed -n 's/^  \([^ ]*\) x.*/\1/p'
}

css_glyph() {
  local codes
  codes=$(sed -n "s/.*\\.ds-badge\\.is-$1::before{content:\"\\(.*\\)\"}.*/\\1/p" "${2:-$CSS}")
  [ -n "$codes" ] || return 1
  printf '%s' "$codes" | perl -CS -e '
    my $s = <STDIN>;
    print join("", map { chr(hex($_)) } grep { length } split /\\/, $s);'
}

test_chat_status_emoji_are_printed_by_the_board_badges() {
  local status want got
  for status in pending finalizing blocked; do
    want=$(chat_emoji "$status")
    [ -n "$want" ] || fail "the chat renderer printed no emoji for $status"
    got=$(css_glyph "$status") || fail "board.css has no $status badge glyph"
    assert_equals "$want" "$got" "the $status badge glyph differs from the chat emoji"
  done
  pass "pending, finalizing and blocked badges print the chat renderer's emoji"
}

test_action_badge_is_the_charcoal_triangle_never_the_green_circle() {
  local green got
  green=$(chat_emoji action)
  assert_equals "🟢" "$green" "the chat renderer no longer prints a green circle for action"
  got=$(css_glyph action) || fail "board.css has no action badge glyph"
  case "$got" in
    ▶*) ;;
    *) fail "the action badge glyph is not the triangle: $got" ;;
  esac
  case "$got" in
    *"$green"*) fail "the action badge prints the green circle" ;;
  esac
  if grep -q '1F7E2' "$CSS"; then
    fail "board.css prints the green circle somewhere"
  fi
  pass "the action badge is the triangle and never the green circle"
}

test_success_badge_is_a_check_mark() {
  local got
  got=$(css_glyph success) || fail "board.css has no success badge glyph"
  assert_equals "✓" "$got" "the success badge glyph is not the check mark"
  grep -q '\.ds-badge\.is-done::before,\.ds-badge\.is-success::before{' "$CSS" \
    || fail "the done badge no longer shares the success glyph rule"
  pass "success and done badges print the check mark"
}

test_bearings_board_inlines_the_board_stylesheet_verbatim() {
  local lines
  lines=$(wc -l < "$CSS" | tr -d ' ')
  sed -n '/^<style>$/,$p' "$TEMPLATE" | sed 1d | head -n "$lines" >"$TMP_ROOT/inlined.css"
  if ! cmp -s "$CSS" "$TMP_ROOT/inlined.css"; then
    fail "the Bearings board template drifted from board.css: $(diff "$CSS" "$TMP_ROOT/inlined.css" | head -5)"
  fi
  pass "the Bearings board template inlines board.css verbatim"
}

fm_test_run \
  test_chat_status_emoji_are_printed_by_the_board_badges \
  test_action_badge_is_the_charcoal_triangle_never_the_green_circle \
  test_success_badge_is_a_check_mark \
  test_bearings_board_inlines_the_board_stylesheet_verbatim
