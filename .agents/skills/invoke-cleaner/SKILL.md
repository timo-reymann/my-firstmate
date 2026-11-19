---
name: invoke-cleaner
description: >-
  Clean up this home when the captain invokes /invoke-cleaner: tear down finished workers, archive Done backlog rows and walk each open row with the captain, remove Firstmate-owned temporary leftovers, then give a short overview and tell the captain to run /compact.
user-invocable: true
metadata:
  internal: true
  version: 1.0.0
---

# invoke-cleaner

`bin/fm-clean.sh` does every deterministic part: it finds, checks eligibility, and acts through the owner scripts.
You supply judgment only: what to ask the captain, and how to word the overview.
Never find, delete, close, or tear down anything yourself, and never work around a skip or a refusal.
Read `bin/fm-clean.sh --help` for the record format and the exact eligibility rules.

Run this only in a session that holds the session lock; a read-only session stops and says why.

## Steps, in this order

1. Make one record file for the run: `run=$(mktemp "${TMPDIR:-/tmp}/invoke-cleaner.XXXXXX")`.
2. **Finished workers.** Run `bin/fm-clean.sh crew --apply --record "$run"`.
   The invocation is the captain's go for this step, because the script tears down only landed, finished work.
   It does so through `bin/fm-teardown.sh` without `--force`.
   A `skip` or `refused` line is final for this run; never retry it with `--force` or by hand.
3. **Backlog.** Run `bin/fm-clean.sh backlog --apply --record "$run"`.
   It archives the Done rows beyond the configured recent-Done retention and prints every open row.
   Walk the open rows with the captain one at a time, one AskUserQuestion per row, in the printed order.
   Name each row by its title and say in plain words why it is still open.
   Offer only the choices that fit the row:
   - **Keep** - always.
   - **Hold until a date** - always; ask for the date and a short reason.
   - **Close with a reason** - not for a row marked `live` (that work is still running).
   - **Dispatch now** - only for a queued row with no `blocked-by` flag.
   Apply each answer at once with `bin/fm-clean.sh decide <id> <choice> --apply --record "$run"`.
   Add `--reason <text>`, `--until YYYY-MM-DD`, or `--words-file <path>` as the choice needs.
   For a row flagged `held=captain`, close and dispatch need the captain's own words in `--words-file`.
   Write the captain's exact answer there: the chosen option and any text they added.
   Never close a captain-held row on your own words or on a default.
   A `dispatch` record hands the row to the normal dispatch intake in `AGENTS.md` section 7; run that intake next.
   If the captain says to stop, keep every row not yet asked about.
4. **Temporary storage.** Run `bin/fm-clean.sh tmp --apply --record "$run"`.
5. **Overview.** Run `bin/fm-clean.sh overview --record "$run"`.
   Turn its output into one short captain-facing message in the `AGENTS.md` section 9 style.
   Lead with outcomes, use no internal terms, and name task ids only when the captain needs them.
   Cover what was cleaned up, what was left and why, what left the backlog, and what the captain decided.
   Add the space freed and what is still open.
   End the message by telling the captain to run `/compact` to clear the conversation context.
   Never run `/compact` yourself.
   Remove the record file afterwards.

## Versioning

`metadata.version` is this skill's semantic version, and it covers this file and `bin/fm-clean.sh` together.
Bump it in the same commit as the change.
Bump the patch for wording or a fix that keeps behavior, and the minor for a new step, choice, or option.
Bump the major when a step may change or remove something it did not before.
