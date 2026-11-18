# Launchers

Three optional launchers for running firstmate day to day.
They live outside `bin/` because they are operator conveniences, not part of the supervision contract.
They need `bash`; `firstmate-herdr` also needs `jq`, [Herdr](https://herdr.dev) protocol 14 or newer, and [uv](https://docs.astral.sh/uv/).
`firstmate-tui` needs `uv`, which fetches Python 3.9 or newer and Textual on first run.
This fork ships no bash fleet view; the firstmate screen is `firstmate-tui`.

## What each one does

- `firstmate` opens the first mate session in the home folder, with Claude Code or OpenCode (see [Choosing the agent](#choosing-the-agent)).
  It resumes the latest session when one changed in the last two hours, and otherwise starts a new one.
  It refuses to start when another session already holds the home's `state/.lock`.
- `firstmate-herdr` builds the firstmate screen in one Herdr tab with three panes: the activity across the top, the first mate bottom left, and the workers bottom right.
  Outside Herdr it builds a workspace named `firstmate-screen` and attaches to it; inside Herdr it builds the layout around the current pane.
  The first mate pane runs `firstmate`; while another session holds the home's `state/.lock`, the pane shows one line with that session's pid and the command to start the first mate there once it quits.
  The workers stay in their own `firstmate` workspace in the same Herdr session, and their tabs keep the `fm-<id>` labels that firstmate uses to find them.
  Options: `--no-attach` builds the layout and stops, `--ratio SHARE` sets the width share of the first mate pane (default 0.6), and `--activity-ratio SHARE` sets the height share of the activity pane (default 0.28).
  Without `uv` on `PATH` it stops with the install hint.
- `firstmate-tui` draws the two views of that screen, written in Python with Textual.
  `--pane activity` is a box with the last 8 events of the [fleet activity ledger](../docs/fleet-ledger.md) as full lines, newest first, and a "NEEDS YOU" count; events that need you (a decision, a blocked worker, a PR ready for review) have a yellow bar.
  `--pane workers` lists the workers, needs-you first, each with its state symbol, kind, task, state, and the age of its last report; a working worker with no report for over an hour shows its age in yellow with `…`.
  Below the list is a live view of the selected worker's screen, read from Herdr about once a second.
  `enter` on a worker starts input mode: the live view title says `INPUT`, and every key you type, including `enter`, arrows, `ctrl` combinations and pasted text, goes to that worker's Herdr pane.
  `escape` (or `ctrl+]`) leaves input mode at once, and the other keys work as before again.
  A worker also uses `escape` to interrupt, so pressing `escape` twice within 0.4 seconds sends one real `escape` to the worker and stays in input mode: the first press leaves, and the quick second press enters input mode again and sends it.
  A pane narrower than 34 columns folds the list to compact tabs and hides the live view.
  `--pane all`, the default, stacks both views in one terminal.
  Every state has its own symbol, so the screen also reads in 16 or 8 colours; `FIRSTMATE_TUI_COLORS` and `FIRSTMATE_TUI_THEME` override the detected colour depth and theme.
  The activity needs the ledger: create `config/fleet-ledger` in the home to turn it on; until then it shows a hint.
- Keys in either view: `↑`/`↓` or `j`/`k` select a worker, `1`-`9` pick one, `tab` selects the next, `enter` types into the worker (where no live view shows, it opens the worker's real Herdr tab), `o` opens the worker's real Herdr tab, `l` opens the full log, `n` shows needs-you events and selects the next worker that needs you, `a` shows all events, `t` shows the selected task's events, `y` copies the selected worker's PR URL, `m` marks its needs-you item read, `?` lists the keys, `r` refreshes, and `q` quits.
  A read mark lasts until the worker's state, report, or PR changes.
- `firstmate-tui` reads `bin/fm-fleet-snapshot.sh --json`, `state/fleet-ledger.jsonl`, and the worker screens, costs no model tokens, and never steers a worker on its own: only the keys you type in input mode reach a worker.
  The only file it writes is `state/firstmate-tui.json` in the home, which holds the selected worker, the activity filter, and the read marks, so both panes share them.
  `--interval SECONDS` sets the refresh period (default 6), and `--once` prints one plain frame of the pane and exits without a terminal or Textual.

## Install

Copy the scripts to a directory on your `PATH`, keeping them together because `firstmate-herdr` finds its siblings next to itself.

```sh
install -m 0755 contrib/firstmate contrib/firstmate-herdr contrib/firstmate-tui "$HOME/.bin/"
```

`firstmate-tui` starts through its `uv run --script` shebang, so `firstmate-tui` and `uv run contrib/firstmate-tui` both work.
Its first run downloads Textual into the uv cache; later runs start offline.

## Choosing the agent

`firstmate` starts `claude` unless a setting names another agent.
It reads, in order, the `FIRSTMATE_AGENT` environment variable and the first non-empty line of `${XDG_CONFIG_HOME:-$HOME/.config}/firstmate/agent`.
The supported values are `claude` and `opencode`; any other value stops the launcher with a message naming the two.

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/firstmate"
echo opencode > "${XDG_CONFIG_HOME:-$HOME/.config}/firstmate/agent"
```

- `claude` runs `claude --permission-mode auto --model sonnet`, with `--continue` when a session is fresh.
- `opencode` runs `opencode --standalone`, with `--continue` when the newest session of the home folder (from `opencode session list`) is fresh, and passes the opening prompt with `--prompt`.
  `--standalone` makes the home's OpenCode plugins run in this process, which OpenCode 2 needs for a first mate; see the [OpenCode adapter](../.agents/skills/harness-adapters/references/harness/opencode.md#primary-integration).
  OpenCode does not submit `--prompt` together with `--continue`, so a resumed session shows the prompt in the composer; press Enter to send it.
  With OpenCode 1, or a version the launcher cannot read, it starts a new session without `--standalone`.
  The launcher passes no model and no permission flag to OpenCode; add them as arguments (for example `firstmate --auto`) or in your OpenCode config.

## Environment overrides

| Variable | Used by | Default |
| --- | --- | --- |
| `FIRSTMATE_DIR` | all | `$HOME/workspace/firstmate` |
| `FIRSTMATE_AGENT` | `firstmate` | unset; `claude` or `opencode`, ahead of the agent file |
| `XDG_CONFIG_HOME` | `firstmate` | `$HOME/.config` (holds `firstmate/agent`) |
| `CLAUDE_CONFIG_DIR` | `firstmate` | `$HOME/.claude` |
| `FIRSTMATE_MAX_AGE_MIN` | `firstmate` | `120` (minutes a session counts as fresh) |
| `FIRSTMATE_PROMPT` | `firstmate` | `Lets start where we left off` |
| `FIRSTMATE_FORCE` | `firstmate` | unset; set it to start despite a live session |
| `FIRSTMATE_DRY_RUN` | `firstmate` | unset; set it to print the command and exit |
| `FIRSTMATE_BIN` | `firstmate-herdr` | `firstmate` next to the script |
| `TUI_BIN` | `firstmate-herdr` | `firstmate-tui` next to the script |
| `HERDR_BIN` | `firstmate-herdr`, `firstmate-tui` | `herdr` |
| `FM_HERDR_SESSION` | `firstmate-herdr` | unset (default session) |
| `FM_FLEET_SNAPSHOT_CMD` | `firstmate-tui` | unset; replaces the snapshot command |
| `FIRSTMATE_TUI_COLORS` | `firstmate-tui` | detected; `truecolor`, `256`, `16` or `8` |
| `FIRSTMATE_TUI_THEME` | `firstmate-tui` | `light` when `COLORFGBG` names a light background, else `dark` |

Extra arguments you pass to `firstmate` are forwarded to the agent.
Edit the `cmd` arrays in the script if you want other default settings.
