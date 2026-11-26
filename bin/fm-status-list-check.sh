#!/usr/bin/env bash
# fm-status-list-check.sh - tell a hand-written work list from genuine fm-status-render.sh output.
#
# Usage: fm-status-list-check.sh [file|-]   (reply text from file, or stdin)
# Exit 0: no hand-written list. Exit 1: found one; offending lines print as "line <n>: <text>". Exit 2: bad usage.
#
# A hand-written list is either:
#   1. a block with a line opening with a status emoji (green, orange, blue, red circle; behind an optional list marker)
#      that is not the renderer's exact group: a column-0 title line directly above, then one to three
#      "  <emoji> <label>" lines in renderer order (action, blocked, finalizing, pending), each non-action line with a ": " note;
#      lines above the title in the same block are ignored, so a lead-in sentence does not hide a group; or
#   2. a heading alone on its line ("Still running:", "In flight", "Work in progress", ...) followed, after at most one
#      blank line, by two or more bullet or numbered lines.
# Fenced code, blockquote lines, and indented code blocks (four or more spaces after a blank line) are skipped.
# Text that copies the renderer's shape by hand passes: nothing in its output marks it as rendered.
set -u

usage() { sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -?*) [ "${1:-}" = "-" ] || { printf 'error: unknown option: %s (try --help)\n' "$1" >&2; exit 2; } ;;
esac
[ $# -le 1 ] || { printf 'error: expected at most one file argument (try --help)\n' >&2; exit 2; }
src="${1:--}"
if [ "$src" != "-" ] && [ ! -r "$src" ]; then
  printf 'error: cannot read %s\n' "$src" >&2
  exit 2
fi

# shellcheck disable=SC2016
AWK_PROG='
function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
function emoji_of(s,   i) {
  for (i = 1; i <= 4; i++) if (index(s, EMO[i]) == 1) return i
  return 0
}
# Strip one bullet or numbered marker, then report the emoji that follows, if any.
function lead_emoji(s,   t) {
  t = ltrim(s)
  sub(/^([-*+]|[0-9]+[.)])[ \t]+/, "", t)
  return emoji_of(t)
}
function is_bullet(s) { return s ~ /^[ ]{0,3}([-*+]|[0-9]+[.)])[ \t]+[^ \t]/ }
function is_list_heading(s,   t) {
  t = tolower(s)
  sub(/^[ ]{0,3}#+[ \t]+/, "", t)
  gsub(/\*\*|__/, "", t)
  sub(/[ \t]*\([^)]*\)[ \t]*:?[ \t]*$/, "", t)
  sub(/[ \t]*:[ \t]*$/, "", t)
  sub(/[ \t]+$/, "", t)
  return t ~ /^(still running|in flight|under way|underway|in progress|work in progress|work under way|open work|open tasks|running tasks|task list|todo|to-do|to-do list|todo list|pending work)$/
}
function note(n, text) {
  if (!(n in seen)) { seen[n] = 1; order[++count] = n; shown[n] = text }
}
# Judge the block collected in blk[1..blkn]; lineno_of[] holds the source line numbers.
function judge_block(   i, first, title_ok, items, rank, last_rank, bad, e, rest) {
  if (blkn == 0) return
  first = 0
  for (i = 1; i <= blkn; i++) if (lead_emoji(blk[i]) != 0) { first = i; break }
  if (first == 0) { blkn = 0; return }
  bad = 0
  # The title is the line directly above the first item: column 0, not itself an emoji or list line.
  if (first == 1) bad = 1
  else {
    t = blk[first - 1]
    if (t ~ /^[ \t]/ || lead_emoji(t) != 0 || is_bullet(t)) bad = 1
  }
  items = blkn - first + 1
  if (items < 1 || items > 3) bad = 1
  last_rank = 0
  for (i = first; i <= blkn && !bad; i++) {
    e = emoji_of(substr(blk[i], 3))
    if (e == 0 || substr(blk[i], 1, 2) != "  ") { bad = 1; break }
    rest = substr(blk[i], 3 + length(EMO[e]))
    if (substr(rest, 1, 1) != " " || substr(rest, 2) ~ /^[ \t]*$/ || substr(rest, 2, 1) == " ") { bad = 1; break }
    rest = substr(rest, 2)
    # green = action (no note); orange, blue, red need a note after a colon.
    if (e != 1 && rest !~ /[^ ]: [^ ]/) { bad = 1; break }
    # Renderer rank: action 0, blocked (red) 1, finalizing (blue) 2, pending (orange) 3.
    rank = (e == 1) ? 0 : (e == 4) ? 1 : (e == 3) ? 2 : 3
    if (rank < last_rank) { bad = 1; break }
    last_rank = rank
  }
  if (bad) for (i = (first > 1 ? first - 1 : first); i <= blkn; i++) note(srcline[i], blk[i])
  blkn = 0
}
function flush_heading() {
  if (heading_line != 0 && bullets >= 2) note(heading_line, heading_text)
  heading_line = 0; bullets = 0; heading_blank = 0
}
BEGIN {
  EMO[1] = "🟢"; EMO[2] = "🟠"; EMO[3] = "🔵"; EMO[4] = "🔴"
  fence = ""
}
{
  line = $0
  sub(/\r$/, "", line)
  n = NR
  # Fenced code blocks.
  if (fence != "") {
    if (match(line, /^[ ]{0,3}(```+|~~~+)[ \t]*$/) && substr(ltrim(line), 1, 1) == substr(fence, 1, 1)) fence = ""
    next
  }
  if (line ~ /^[ ]{0,3}(```+|~~~+)/) {
    judge_block(); flush_heading()
    fence = substr(ltrim(line), 1, 1)
    next
  }
  # Quoted text is not read. A line indented four or more spaces is an indented code block only when it
  # starts a block; under a paragraph line it is a lazy continuation and is read.
  if (line ~ /^[ \t]*>/) { judge_block(); flush_heading(); next }
  if (line ~ /^( {4,}|\t)/ && blkn == 0 && heading_line == 0) next
  if (line ~ /^[ \t]*$/) {
    judge_block()
    if (heading_line != 0) {
      if (bullets == 0 && heading_blank == 0) heading_blank = 1
      else flush_heading()
    }
    next
  }
  # Heading tracking (shape 2).
  if (heading_line != 0) {
    if (is_bullet(line)) { bullets++; blk[++blkn] = line; srcline[blkn] = n; next }
    flush_heading()
  }
  if (is_list_heading(line)) {
    judge_block()
    heading_line = n; heading_text = line; bullets = 0; heading_blank = 0
    next
  }
  blk[++blkn] = line
  srcline[blkn] = n
}
END {
  judge_block()
  flush_heading()
  for (i = 1; i <= count; i++) printf "line %d: %s\n", order[i], shown[order[i]]
  exit (count > 0 ? 1 : 0)
}
'

if [ "$src" = "-" ]; then
  awk "$AWK_PROG"
else
  awk "$AWK_PROG" "$src"
fi
