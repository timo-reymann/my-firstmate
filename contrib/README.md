# Launchers

Three optional shell launchers for running firstmate day to day.
They live outside `bin/` because they are operator conveniences, not part of the supervision contract.
They need `bash`; `firstmate-herdr` and `firstmate-fleet` also need `jq`, and the Herdr pair needs [Herdr](https://herdr.dev) protocol 14 or newer.

## What each one does

- `firstmate` opens the first mate session in the home folder.
  It resumes the latest Claude session when one changed in the last two hours, and otherwise starts a new one.
  It refuses to start when another session already holds the home's `state/.lock`.
- `firstmate-herdr` builds a Herdr workspace named `firstmate`: the first mate on the left and the fleet view on the right.
  Inside Herdr it splits the current pane instead.
  Options: `--no-attach` builds the layout and stops, `--ratio SHARE` sets the width share of the first mate pane (default 0.72).
- `firstmate-fleet` is a read-only fleet view built on `bin/fm-fleet-snapshot.sh --json`.
  It costs no model tokens.
  Keys: `j`/`k` or arrows move, `enter` jumps to the task tab in Herdr, `r` refreshes, `q` quits.
  `--once` prints one plain frame and exits.

## Install

Copy the scripts to a directory on your `PATH`, keeping them together because `firstmate-herdr` finds its siblings next to itself.

```sh
install -m 0755 contrib/firstmate contrib/firstmate-herdr contrib/firstmate-fleet "$HOME/.bin/"
```

## Environment overrides

| Variable | Used by | Default |
| --- | --- | --- |
| `FIRSTMATE_DIR` | all | `$HOME/workspace/firstmate` |
| `CLAUDE_CONFIG_DIR` | `firstmate` | `$HOME/.claude` |
| `FIRSTMATE_MAX_AGE_MIN` | `firstmate` | `120` (minutes a session counts as fresh) |
| `FIRSTMATE_PROMPT` | `firstmate` | `Lets start where we left off` |
| `FIRSTMATE_FORCE` | `firstmate` | unset; set it to start despite a live session |
| `FIRSTMATE_DRY_RUN` | `firstmate` | unset; set it to print the command and exit |
| `FIRSTMATE_BIN` | `firstmate-herdr` | `firstmate` next to the script |
| `FLEET_BIN` | `firstmate-herdr` | `firstmate-fleet` next to the script |
| `HERDR_BIN` | `firstmate-herdr`, `firstmate-fleet` | `herdr` |
| `FM_HERDR_SESSION` | `firstmate-herdr` | unset (default session) |
| `FM_FLEET_SNAPSHOT_CMD` | `firstmate-fleet` | unset; replaces the snapshot command |

`firstmate` starts Claude with `--permission-mode auto --model sonnet`.
Edit the `cmd` arrays in the script if you want other settings; extra arguments you pass are forwarded to Claude.
