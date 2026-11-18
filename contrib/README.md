# Launchers

Four optional launchers for running firstmate day to day.
They live outside `bin/` because they are operator conveniences, not part of the supervision contract.
They need `bash`; `firstmate-herdr` and `firstmate-fleet` also need `jq`, and the Herdr pair needs [Herdr](https://herdr.dev) protocol 14 or newer.
`firstmate-tui` needs [uv](https://docs.astral.sh/uv/), which fetches Python 3.9 or newer and Textual on first run.

## What each one does

- `firstmate` opens the first mate session in the home folder, with Claude Code or OpenCode (see [Choosing the agent](#choosing-the-agent)).
  It resumes the latest session when one changed in the last two hours, and otherwise starts a new one.
  It refuses to start when another session already holds the home's `state/.lock`.
- `firstmate-herdr` builds a Herdr workspace named `firstmate`: the first mate on the left and the fleet view on the right.
  Inside Herdr it splits the current pane instead.
  The workers stay in the same Herdr session.
  Options: `--no-attach` builds the layout and stops, `--ratio SHARE` sets the width share of the first mate pane (default 0.72).
  The right pane runs `firstmate-tui` when `uv` is on `PATH`, and `firstmate-fleet` otherwise.
- `firstmate-tui` is a read-only fleet view with an activity feed, written in Python with Textual.
  It shows the home and refresh time, a "Needs you" strip (PRs ready for review, workers waiting on a decision, blocked workers), a task table (task, kind, project, state, and the age of the last status report), and the last 30 events of the [fleet activity ledger](../docs/fleet-ledger.md) with PR URLs in full.
  It reads `bin/fm-fleet-snapshot.sh --json` and `state/fleet-ledger.jsonl`, costs no model tokens, writes nothing, and never steers a worker.
  The feed needs the ledger: create `config/fleet-ledger` in the home to turn it on; until then the feed shows a hint.
  Keys: `j`/`k` or arrows move, `enter` jumps to the task tab in Herdr, `r` refreshes, `f` cycles the state filter, `q` quits.
  `--interval SECONDS` sets the refresh period (default 6), and `--once` prints one plain frame and exits without a terminal.
- `firstmate-fleet` is the same fleet view in plain bash, built on `bin/fm-fleet-snapshot.sh --json`, without the feed.
  It costs no model tokens.
  Keys: `j`/`k` or arrows move, `enter` jumps to the task tab in Herdr, `r` refreshes, `q` quits.
  `--once` prints one plain frame and exits.

## Install

Copy the scripts to a directory on your `PATH`, keeping them together because `firstmate-herdr` finds its siblings next to itself.

```sh
install -m 0755 contrib/firstmate contrib/firstmate-herdr contrib/firstmate-fleet contrib/firstmate-tui "$HOME/.bin/"
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
| `FIRSTMATE_FLEET_VIEW` | `firstmate-herdr` | unset; `tui` or `bash` forces that fleet view |
| `FLEET_BIN` | `firstmate-herdr` | `firstmate-fleet` next to the script; setting it selects the bash view unless `FIRSTMATE_FLEET_VIEW=tui` |
| `TUI_BIN` | `firstmate-herdr` | `firstmate-tui` next to the script |
| `HERDR_BIN` | `firstmate-herdr`, `firstmate-fleet`, `firstmate-tui` | `herdr` |
| `FM_HERDR_SESSION` | `firstmate-herdr` | unset (default session) |
| `FM_FLEET_SNAPSHOT_CMD` | `firstmate-fleet`, `firstmate-tui` | unset; replaces the snapshot command |

Extra arguments you pass to `firstmate` are forwarded to the agent.
Edit the `cmd` arrays in the script if you want other default settings.
