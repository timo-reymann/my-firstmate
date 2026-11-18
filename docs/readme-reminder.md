# README reminder PreToolUse hook

This document is the authoritative contract for the advisory README reminder hook.
`bin/fm-readme-reminder-pretool.sh` is the only implementation, registered for the Bash tool in the tracked `.claude/settings.json`.

## Purpose and boundary

This fork keeps a "Changes from upstream" list in `README.md`.
When a commit changes user-visible material but leaves README.md alone, the list drifts.
The hook reminds the agent to update the list in the same branch.

It is advisory only.
It never denies a command, never blocks a commit, and never changes pipeline behavior.
It returns Claude's `additionalContext` and exits 0 in every case.

## When it fires

It fires on a `git commit` command when all of these hold:

- The commit includes user-visible material: `bin/`, `.agents/skills/`, `skills/`, `.claude/`, `.github/workflows/`, `AGENTS.md`, or `skills-lock.json`.
  The set is the staged files from `git diff --cached --name-only`, plus tracked modifications when the command carries `-a` or `--all`.
- The commit does not include `README.md`.
- `README.md` has a "Changes from upstream" heading, so the upstream template is unaffected.
- The commit is not a `docs:` or `docs(...)` commit, a `Merge` commit, or a `--fixup`, `--squash`, or `--no-edit` commit.
- The same file set was not already reminded about in this session.

## Once per file set

The marker is an empty file under `fm-readme-reminder/` in the repository's git directory, keyed by session id and file set.
A task worktree's cleanup removes it with the worktree.

## Fail-open behavior

Malformed or empty input, missing `jq` or `git`, a missing repository, and any other error print nothing and exit 0.
A payload from another host (Cursor stamps `cursor_version`) is skipped, because that host loads this registration as a duplicate.

Tests: `tests/fm-readme-reminder-pretool.test.sh`.
