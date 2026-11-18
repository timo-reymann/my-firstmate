# Runtime backend verification

Audience: maintainer verification.

This record contains reusable version-scoped evidence for active runtime guarantees.
The backend guides own current setup, safety boundaries, and limitations.
Exact task chronology, branch names, temporary homes, local paths, process ids, thread ids, and delivery transcripts remain in private reports or PR evidence.

## Polytoken worker lifecycle

Verified on 2026-10-14 with Polytoken 0.9.0 on macOS arm64 using the tmux worker path.
[Polytoken verification](polytoken.md) owns the commands, session-model proof, and lifecycle output; its credentialed live guard refreshes the evidence.
This does not verify a Polytoken primary, secondmate, or native Herdr pane.

## Harness detection precedence

Firstmate's own harness comes from two kinds of evidence, and `bin/fm-harness.sh` owns how they combine: an environment marker names its harness, and the nearest harness process in the parent chain proves who owns the process tree.
A marker alone is not proof of ownership, because it is ordinary environment state that a child inherits and a terminal multiplexer can replay into an unrelated session.
Verified on 2026-09-02 on Linux 7.1.12 with the portable regression, which builds every case from real renamed processes and no installed harness:

```sh
bin/fm-test-run.sh tests/fm-harness-precedence.test.sh
```

Observed output:

```text
ok - a markerless harness keeps its identity under an inherited foreign marker
ok - a harness that publishes a marker inside its own process tree is unchanged
ok - with ancestry silent, the marker layer and its cursor-first ordering still decide
ok - a retained cursor marker does not rename a nested claude worker
ok - an agreeing marker keeps Pi's finer identity that ancestry cannot prove
ok - an interpreter script-path match answers alone but never outranks a marker
ok - a native harness binary under an interpreter shim decides at comm strength
ok - a harness that is pid 1 of its own namespace is examined, not skipped
ok - the descent probe reaches comm strength where the top-of-session probe sees only args
ok - the descent probe reports no verdict from a sibling branch detection cannot reach
ok - a foreign args-only verdict at the deepest vantage leaves the comm-strength identity intact
ok - equal-depth descent ties prefer the comm-strength leaf regardless of spawn order
ok - session start renders the Codex protocol for a Codex primary holding a retained CLAUDECODE
FM_TEST_SUMMARY total=1 failed=0 skipped_gate=0 duration_ms=3666
```

Before that boundary existed, a Codex session started from an environment that had retained `CLAUDECODE=1` reported `claude`, and session start emitted Claude's Stop-owned supervision protocol to a Codex primary.
The same live shape, reproduced with a real process named `codex` and no installed harness, now reports `codex` with the marker present and `claude` with the marker present and ancestry blinded, which is what proves the case is not vacuous.

### A real Codex session holding a retained Claude marker

The portable regression builds its process tree from renamed executables, so the same guarantee is proven again against the real installed Codex.
`codex sandbox` runs a command under the installed native binary with no model turn, inside a PID namespace where that binary is pid 1 and the command is pid 2.
Verified on 2026-09-01 with codex-cli 0.152.0 on Linux 7.1.10, with both Claude markers retained in the launching environment:

```sh
CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli codex sandbox bash -c \
  'cd <checkout> && bin/fm-harness.sh; bin/fm-harness.sh ancestry; bin/fm-supervision-instructions.sh'
```

Against the parent commit, with `CLAUDECODE=1` and `CLAUDE_CODE_ENTRYPOINT=cli` confirmed present in the probe's own environment and the chain reading pid 2 `bash` to pid 1 `codex`:

```text
verdict=claude
SUPERVISION OPERATING INSTRUCTIONS - primary harness: claude
Mode: Claude Stop-hook-owned supervision.
```

With the current boundaries in place, from the same command and the same process chain:

```text
verdict=codex
ancestry=comm codex
SUPERVISION OPERATING INSTRUCTIONS - primary harness: codex
Mode: Codex foreground checkpoint.
```

Two boundaries are load-bearing here, and the marker-versus-ancestry precedence above is only the first.
The walk also used to stop as soon as the next pid was 1, on the assumption that pid 1 is always init.
That assumption inverts inside a PID namespace, where the harness is pid 1: the walk returned no ancestry at all, so the retained marker won by default even with precedence corrected.
The walk now examines that top process before stopping, which costs one `ps` call and can introduce no false positive, because a host's real pid 1 (init, systemd, launchd) matches no harness name.
The portable regression asserts both directions of that case: a host-shaped pid 1 still leaves the marker to answer, and a harness at pid 1 outranks it.

Run on the host under Claude Code 2.1.252 with the same two markers set, the same probe reports `claude`, `comm claude`, and Claude's Stop-owned protocol, so the correction does not trade one misidentification for its inverse.

### Real harness process names behind the walk

The detection half of the opt-in drift guard asks the ancestry walk what it makes of each INSTALLED harness's real running process:

```sh
FM_HARNESS_LIVENESS_DRIFT=1 bin/fm-test-run.sh tests/fm-harness-liveness-drift-live-e2e.test.sh
```

The guard probes the upward path between the deepest foreground descendant of the pane process and the pane process itself, and reports each distinct verdict that vantage set produces.
Observed on 2026-09-02 for the harnesses installed on that machine:

```text
# claude 2.1.258 (Claude Code): title='claude' foreground=[claude ]
# claude 2.1.258 (Claude Code): ancestry verdicts=[comm claude]
# codex codex-cli 0.152.0: title='node' foreground=[node codex ]
# codex codex-cli 0.152.0: ancestry verdicts=[comm codex;args codex]
```

The verdicts are reported deepest first, so Codex's native child answers before the shim above it.
When eligible foreground descendants tie at the greatest depth, the probe prefers a leaf whose own verdict reaches comm strength; if none does, it keeps the first leaf, so process-table ordering cannot hide an equally deep native harness binary behind an args-strength interpreter.

Codex ships as a `node` npm shim that spawns its native `codex` binary as a foreground child, which is why its two verdicts differ: the pane process is identified only from the shim's script path, and the native child is what carries the process name.
That difference is the reason the guard cannot probe the pane process alone.
The guarantee this guard holds is a strength claim, not only an identity one, because `detect_own` hands an args-strength verdict straight back to a retained foreign marker.
A pane-only probe would have observed `args codex`, passed, and gone on passing if a later release stopped spawning the native child, while real sessions silently regressed to the original bug.
Probing from below asks the question from the vantage a tool subprocess actually occupies, so the guard can require comm strength somewhere in the session and require every comm-strength vantage to name the same harness.
The vantage set stops at the upward path rather than the whole subtree, because `harness_ancestry` only ever climbs and a sibling branch is therefore a vantage firstmate's own detection can never occupy.
The reject-other-harness cross-check judges comm-strength vantages only, because an args-strength verdict is path-ambiguous by construction: a harness-spawned MCP server running as `node <home>/.claude/mcp/<server>.js` answers `args claude` purely from the `.claude` path component, and such a server is normally a child of the agent binary, so it can be the deepest descendant and sit on this path.
That narrowing changes only which vantages the cross-check judges; the comm-strength requirement itself is unchanged.
A single-process harness has no descendant that adds a distinct verdict, which is why `claude` reports one.
The portable regression pins every half without any harness installed: `tests/fm-harness-precedence.test.sh` asserts that this two-process topology decides at comm strength, that the descent probe reaches a strength the top-of-session probe cannot, that a sibling branch answering a foreign harness contributes no verdict, that a foreign args-only verdict at the deepest vantage leaves the comm-strength identity intact, and that equal-depth ties choose the comm-strength leaf regardless of process ordering.
The run did not reach `opencode`, `kimi`, or `muse`, which were not installed, and stopped at the same pre-existing liveness failure for `cursor` 3.18.9, whose resolved binary on that machine is the editor rather than `cursor-agent`; those adapters are unverified by this run.

## tmux

Foreground-process behavior was verified on 2026-07-07 with tmux 3.6a on macOS.

```sh
tmux new-session -d -s fmtest -n testwin
tmux display-message -p -t fmtest:testwin '#{pane_current_command}'
tmux send-keys -t fmtest:testwin 'sleep 30' Enter
tmux display-message -p -t fmtest:testwin '#{pane_current_command}'
tmux send-keys -t fmtest:testwin C-c
tmux display-message -p -t fmtest:testwin '#{pane_current_command}'
```

Observed output:

```text
zsh
sleep
zsh
```

A persistent parent shell waiting for a child remained reported as the parent process, while a shell that directly execed a simple command changed identity with the process itself.

### Agent liveness name sources

Hermes Agent v0.21.7 was verified as a tmux worker on Linux on 2026-11-02: native Node TUI / Python module argv yielded `alive`, and the tool-side harness detector returned `hermes`.
[Hermes verification](hermes.md) owns the dated native hook, composer, profile-safety, and lifecycle evidence.
Refresh it with `FM_HERMES_SIGNALS_LIVE=1 FM_HERMES_LIVE_HOME="$throwaway_root" bash bin/fm-test-run.sh tests/fm-hermes-signals-live-e2e.test.sh`.

The earlier record that every harness is observed under its own `#{pane_current_command}` no longer holds and has been replaced by the per-harness evidence below.
In this macOS run that reading reflected a rewritable process title rather than stable executable identity, so it is now one of two independent name sources rather than the sole basis of a verdict.

The seven primary-capable adapters were relaunched on 2026-08-03 with tmux 3.6a on macOS 26.5.2 arm64, each on a private socket in an isolated lab.

```sh
tmux -L "$socket" new-window -d -t "$session:" -n "$harness" -c "$wt" -- "$bin"
tmux -L "$socket" display-message -p -t "$session:$harness" '#{pane_current_command}'
ps -t "${tty#/dev/}" -o pgid=,tpgid=,comm=      # rows where pgid = tpgid
```

Observed identities, and the resulting verdict:

| Harness | Version | `#{pane_current_command}` | Foreground `comm` | Verdict |
| --- | --- | --- | --- | --- |
| claude | 2.1.220 | `2.1.220` | `claude` | alive |
| codex | codex-cli 0.146.0 | `codex` | `codex` | alive |
| opencode | 1.18.11 | `opencode` | `opencode` | alive |
| kimi | 0.31.1 | `kimi` | `kimi` | alive |

In that 2026-08-03 run, Claude Code was the only harness whose title did not attribute it; every other adapter was attributed by both sources.
Codex reported `codex-aarch64-a` at 0.145.0 and `codex` at 0.146.0, and Kimi Code reported `kimi-code` as its foreground `comm` at 0.29.1 and `kimi` at 0.31.1, so these identities move between ordinary patch releases in both directions.
That is the evidence for treating any single process name as a surface under vendor control rather than a stable contract.

The crewmate-only Muse Code 0.1.0-R708.1 adapter was verified separately on 2026-08-05 against tmux on macOS arm64.
Its installed `muse-bin-0.1.0-R708.1` foreground identity classified `alive`, while `musescore`, `amuse`, `muse-binary`, and `muse-bind` remained ambiguous in the portable regression.
[`muse.md`](muse.md#process-identity) owns the artifact identity and launcher evidence for that verification.

The crewmate/scout-only Command Code 1.74.1 adapter was verified on 2026-10-05 against tmux 3.7c and a Herdr 0.9.3 lab session on Linux x86_64.
Its node process sets its title to `command-code`, the anchored foreground identity that classified `alive` on both backends, while `command-code-helper` remained ambiguous in the portable regression.
[`commandcode.md`](commandcode.md) owns that evidence, and `FM_COMMANDCODE_SIGNALS_LIVE=1 bin/fm-test-run.sh tests/fm-commandcode-signals-live-e2e.test.sh` refreshes it.

The crewmate/scout-only Rovo CLI 202609.1.2 adapter added `*rovo*` to the same glob family as `*kimi*` in the shared process-name classifier (now `fm_agent_process_classify_name` in `bin/fm-agent-process-lib.sh`), and was relaunched live under tmux 3.6a in an isolated private socket.
`#{pane_current_command}` reported the truncated on-disk binary name `atlassian_cli_r` - macOS's 15-char `comm` truncation cuts `atlassian_cli_rovodev` off just before the `rovo` substring begins, the same truncation-volatility class codex/kimi's own patch-release name drift shows above - while the foreground ps-based `comm` correctly reported `rovo`, so `fm_backend_tmux_agent_state` returned `alive` through that primary source; the two-independent-name-sources design is exactly why the truncated title does not break the verdict.
[`rovo.md`](rovo.md#backend-liveness-tmux-verified-live-herdr-placement-verified-live-with-a-herdr-side-agent-detection-gap) owns the fuller record, including the busy/interrupt/exit facts captured in that same live tmux session and the herdr agent-detection gap found when herdr placement was verified live in an isolated lab session.

Bounded observed output:

```text
foreground comms:
  zsh
  .../instbin/muse-bin-0.1.0-R708.1
classify each:
  zsh                            -> shell
  muse-bin-0.1.0-R708.1          -> agent
fm_backend_agent_state tmux museliv:zsh
alive
```

`#{pane_current_command}` and foreground `ps -o comm=` read different name fields, but which one preserves executable identity is platform-dependent.
On macOS the pane command reflected the rewritable title while the full install path could survive in `ps -o comm=`; in the Linux portable regression those roles reversed for the version-named native executable, with the identifying path retained in argv[0].
The classifier therefore accepts a harness basename first, then an exact harness path component in the full executable path, then the same component in argv[0], without depending on which field carries it on a given platform.

The portable regression is CI-enforced.
The real-harness drift guard spends no model tokens, so under the policy in `.agents/skills/firstmate-coding-guidelines/SKILL.md` it runs by default wherever tmux is installed and reports a capability skip elsewhere; `FM_HARNESS_LIVENESS_DRIFT=1` additionally turns an absent tool into a failure.
Run the live guard after any harness upgrade and before trusting or refreshing the table above:

```sh
FM_HARNESS_LIVENESS_DRIFT=1 bin/fm-test-run.sh tests/fm-harness-liveness-drift-live-e2e.test.sh
```

### 2026-09-06 default-on drift refresh, and the Cursor editor CLI collision

Running the guard with no variable set on macOS 26.5.2 arm64 checked 8 installed harnesses and classified every one `alive`:

```text
# claude 2.1.263 (Claude Code): title='2.1.263' foreground=[/Users/kunchen/.local/bin/claude <defunct> <defunct> ]
# codex codex-cli 0.147.0: title='codex' foreground=[/opt/homebrew/bin/codex ]
# opencode 1.18.29: title='opencode' foreground=[/opt/homebrew/bin/opencode ]
# pi 0.84.4: title='pi-launcher' foreground=[/opt/homebrew/bin/pi-signed .../pi ]
# pi-signed 0.84.4: title='pi-launcher' foreground=[/opt/homebrew/bin/pi-signed .../pi ]
# grok grok 1.0.13 (5e9a58528b76) [stable]: title='grok-1.0.13-mac' foreground=[/Users/kunchen/.local/bin/grok ]
# cursor 2026.09.02-c22c1a3: title='node' foreground=[/Users/kunchen/.local/bin/cursor-agent ]
# muse Muse Code 1.0.3 (1.0.3-R2198.1): title='muse-bin-1.0.3-' foreground=[/Users/kunchen/.local/bin/muse-bin-1.0.3-R2198.1 ]
# checked 8 installed harness(es)
```

The first default-on run failed on Cursor with `LIVENESS DRIFT: cursor unknown is running but classifies 'missing'`, observed title `zsh`.
The classifier was not at fault: the guard resolved the harness through a generic `command -v cursor`, which on a machine that also has the Cursor editor finds `~/.local/bin/cursor` - the editor launcher, not the agent.
That binary exits immediately, leaving a bare shell in the pane.
The guard now asks `fm_cursor_resolve_binary` first for `cursor`, which is the same verified owner `bin/fm-spawn.sh` uses, so the probe launches `cursor-agent` and the editor CLI can no longer masquerade as the harness.

Bounded output from the 2026-08-03 run that produced the first table above:

```text
ok - harness liveness: claude 2.1.220 (Claude Code) classifies alive
# claude 2.1.220 (Claude Code): title='2.1.220' foreground=[claude ]
# checked 7 installed harness(es)
```

### Harness-adapter instruction routing

Two checks keep the evidence boundaries separate.
`tests/fm-harness-adapter-references.test.sh` parses the router's declared JSON contract as normalized data and proves every selected reference is readable, which is structural evidence only.
`tests/fm-harness-adapter-instructions-live-e2e.test.sh` is an opt-in development check that sends the directly loaded router and every operation scenario across all nine harness identities to a local Ollama model, requires the generated plan as normalized JSON, and makes no external-provider call.

```sh
FM_HARNESS_ADAPTER_INSTRUCTION_EVAL=1 FM_HARNESS_ADAPTER_LOCAL_MODEL=ambient-router-gemma4:e4b bin/fm-test-run.sh tests/fm-harness-adapter-instructions-live-e2e.test.sh
```

That local evaluation demonstrates instruction-driven scenario selection, but it does not claim that a native harness loaded the selected files.
The guard prints the exact installed version or unavailable status for every native harness so absent tools and unexercised provider transports remain explicit rather than becoming passes.
Native loader behavior still requires the applicable live agent-tool check; no uniform deterministic zero-provider transport currently spans Claude, Codex, and OpenCode, and the other tools remain unavailable where their binaries are absent.

Bounded output from the 2026-08-29 local run:

```text
ok - local model ambient-router-gemma4:e4b selected every operation scenario and all nine harness identities
# native loader not claimed: claude 2.1.220 (Claude Code) is installed, but this harness-neutral evaluation does not exercise its provider transport
# native loader not claimed: codex 0.147.0-alpha.6+local.4 is installed, but this harness-neutral evaluation does not exercise its provider transport
# native loader not claimed: opencode 1.14.48 is installed, but this harness-neutral evaluation does not exercise its provider transport
# native loader not claimed: pi 0.84.0 is installed, but this harness-neutral evaluation does not exercise its provider transport
# unverified native loader: pi-signed is not installed on this machine
# unverified native loader: grok is not installed on this machine
# unverified native loader: kimi is not installed on this machine
# unverified native loader: cursor is not installed on this machine
# unverified native loader: muse is not installed on this machine
# installed native tools recorded without overstating loader coverage: 4
# unavailable native tools: pi-signed grok kimi cursor muse
```

The current classifier matrix and its refresh guard are recorded in [Composer classification matrix](#composer-classification-matrix), with portable shape coverage in `tests/fm-composer-lib.test.sh` and `tests/fm-composer-ghost.test.sh`.
Kimi pointer delivery and OpenCode busy-queue behavior remain pinned by `tests/fm-kimi-harness.test.sh`, `tests/fm-tmux-submit-busy.test.sh`, and `tests/fm-composer-lib.test.sh`.
Herdr's Claude idle-native submit confirmation is pinned by `tests/fm-backend-herdr.test.sh` and refreshed by `FM_HERDR_SUBMIT_CONFIRM_LIVE=1 tests/fm-herdr-submit-confirm-live-e2e.test.sh`.

### Cleanup endpoint identity

The cleanup identity boundary was validated on 2026-07-28 with tmux 3.6a and metadata fixtures for every backend supported at that time.

```sh
tests/fm-teardown-endpoint-safety.test.sh
tests/fm-teardown.test.sh
tests/fm-backend-herdr.test.sh
tests/fm-backend-orca.test.sh
```

Bounded output from the 2026-07-28 incident regression, taken while Zellij, cmux, and Paseo were still supported backends:

```text
ok - fm-teardown: missing, empty, malformed, ambiguous, and task-mismatched endpoints refuse before every mutation or runtime call
ok - cleanup identity: valid tmux, Herdr, Zellij, Orca, cmux, and Paseo records validate while every empty backend target refuses
ok - tmux backend: direct empty target returns nonzero without invoking tmux
ok - process cleanup: creation-time PID identity removes only the exact child and preserves the control child
ok - fm-teardown: dedicated-socket invalid cleanup preserves target/control and valid cleanup removes only the exact target
```

The dedicated tmux cell removed ambient tmux variables, required a socket-bound wrapper, kept one target and one independent control window, and proved the wrapper was not called for invalid metadata or a direct empty target.
Valid cleanup removed only the exact task-bound target and left the control window live.
The metadata-only validation covers tmux, Herdr, and Orca before backend dispatch.
Claude, Codex, OpenCode, Kimi, Cursor, and Muse share that backend cleanup boundary; their harness-specific hook files, tokens, transcript bindings, and session-log sidecars are cleaned only after it, so no harness needs a separate endpoint parser.

### Endpoint close

A reported close failure costs teardown every durable record of the task, so what each backend's close actually returns was measured before that status was given any authority.
Verified on 2026-09-14 with tmux 3.7c by driving `fm_backend_kill` against real tmux endpoints, and the Orca arm by driving `fm_backend_orca_kill` under a search path with no `orca` on it.

```sh
tests/fm-teardown-endpoint-safety.test.sh
tests/fm-backend-orca.test.sh
```

```text
ok - fm-teardown: a close that genuinely failed refuses and keeps the record naming the surviving endpoint, and the same teardown finishes once the close works
ok - fm-teardown: --force continues past a close it could not make while still reporting it, and the same case refuses without --force
ok - fm-teardown: a close re-read that could not run refuses, while a definitively absent session or server still completes silently
ok - fm-teardown: forced secondmate cleanup still refuses on a child endpoint close that failed
ok - fm-teardown: an Orca close its missing CLI never attempted refuses even under --force, keeping the record naming the terminal
ok - fm-teardown: an already-exited endpoint, and a server that is already gone, still complete cleanup silently
ok - fm_backend_orca_kill: a close its missing CLI never attempted reports the failure instead of a success
```

An endpoint that is already legitimately gone returns 0 silently on every arm covered by this entry, so ordinary cleanup of an already-exited session is unchanged: real tmux returns 0 for a live window, for a re-close of that same gone window, and for a close into a session whose whole server has exited.
The refusal is reached only through a close that could not do its job, and each arm reports only what it can prove:

| Backend | already gone | a close that failed |
| --- | --- | --- |
| tmux | 0, silent | 1, resolved by re-reading the window's exact recorded identity; a read that itself could not run refuses rather than passing for absence |
| orca | 0, silent | 1 when a missing CLI means no close was attempted; 0 for a close command that failed after the CLI accepted it |
| herdr | 0, silent | 0 from this arm; `bin/fm-teardown.sh` gates every Herdr record removal on `fm_backend_herdr_endpoint_confirmed_gone` instead |

The Orca arm's failed-close case still reports 0 because it needs a presence re-read taken after its own close, and the close-then-read timing that re-read depends on cannot be established without the real Orca binary.
Guessing it is what a refusal must never rest on: a gate that refused an already-exited session would break ordinary cleanup on every task, which is a worse failure than the stranded endpoint it would be trying to prevent.
tmux's re-read is deliberately exact - `=session` plus a whole-line window-name match - because a prefix match would read a neighboring window as this window's survivor, which is the same exactness the cleanup identity boundary above already requires.
It is also deliberately conservative about the read itself, sharing `fm_backend_tmux_window_inventory` with `fm_backend_tmux_agent_state` so both mean the same thing by an absent session: only a definitive missing-session, missing-server, or connect-error response proves the window gone.
Any other read failure - a momentarily unresponsive server, or a teardown PATH without tmux on it - refuses, because a read that could not run is not evidence of absence.

Two bounds of the refusal are known and deliberately not closed here.

`--force` overrides it at exactly one site, the generic close for backends other than Herdr and Orca.
That is the only close where continuing is actually reachable: the worktree is already returned by then and nothing after it needs the backend that could not close, so `--force` - the operator's existing authority to discard a task's records - can mean something there.
A forced run still prints the full diagnosis naming the backend, the target, and that the close failed, so what may survive is never silent.
It states what `--force` authorizes rather than what will have happened, because the later inactive-reconcile delivery gate can still stop it with every record retained.

The Orca close refuses under `--force` too.
The step immediately after it removes the Orca worktree through the same CLI whose absence is the only thing that arm ever reports, so a forced continue would die there having removed nothing while claiming the records were already gone.
The two child close sites inside forced secondmate cleanup also keep refusing: that path is only ever reached under `--force`, so honoring force there would delete the refusal rather than override it, and would contradict the adjacent Herdr child gate that stops forced cleanup for the same hazard.

[`bin/fm-teardown.sh`](../../bin/fm-teardown.sh)'s header and `endpoint_close_refusal` comment own cleanup ordering and the limits of record retention after a close refusal.
Reconcile the surviving endpoint rather than assuming the retained record guarantees a later retry.

Both directions are proven non-vacuous.
Restoring the swallowed status makes the refusal case report `teardown <id> complete`, delete the endpoint record, and leave the window live.
Keeping the refusal but dropping the exact re-read makes an already-exited endpoint refuse its own cleanup, and also fails the cleanup identity case above.
Letting an unreadable inventory pass for absence makes the unreadable case complete and remove the record while the window is still there.
Removing the `--force` arm makes the forced generic case refuse; honoring `--force` at the child sites makes forced secondmate cleanup continue past a child endpoint it could not close, and honoring it at the Orca site makes that forced cleanup abort on the missing CLI after announcing that it was continuing.
Restoring `fm_backend_orca_kill`'s swallowed tool check makes the CLI-absent adapter case report success.
Dropping the retention-is-not-durable line makes the refusal claim a retention teardown does not own.

## Kimi folder prompt

Verified on 2026-10-23 on Linux with tmux 3.6 against Kimi Code CLI 2.3.0 and 2.3.1, each installed into an isolated prefix and launched with a disposable home and its updater off.
Kimi 2.3.0 reworded its folder prompt: the options read `Trust and continue` and `Exit`, a directory with no project MCP servers reads `No project integrations or instructions to activate.`, and a directory that declares project MCP servers announces them as `Start N MCP server(s) automatically` over `Config: <file>`.
It also reads a root `.mcp.json` at the git worktree root as a project declaration, which its documentation does not name; the prompt's `Config:` line names whichever file declared the servers.
Pressing Enter on an announcing prompt started the declared stdio command before any login, so `bin/fm-spawn.sh` never answers one.
In a pane too short for the prompt Kimi shows only the title and `Enlarge terminal to review sources. Esc exit.`, and in a pane a few rows taller it keeps the complete dialog and pages the lines between the directory and the options, marked `←→ page · N / M`, which can hide the announcement.
`bin/fm-kimi-trust-lib.sh` owns the predicates and `tests/captures/kimi-code-2.3.0/README.md` the recorded panes.
The default-on live guard launches the installed Kimi bare in a private tmux server, spends no tokens, needs no login, and refreshes this evidence:

```sh
FM_KIMI_TRUST_PROMPT_LIVE=1 bin/fm-test-run.sh tests/fm-kimi-trust-prompt-live-e2e.test.sh
```

Observed output against 2.3.0; 2.3.1 printed the same lines with its own version:

```text
# kimi 2.3.0: plain prompt options read 'Trust and continue' / 'Exit'
ok - kimi 2.3.0: a plain directory's folder prompt is the complete dialog, and Enter clears it into a ready pane
# kimi 2.3.0: root-mcp-json prompt announces: Start 1 MCP server automatically;Config: .mcp.json;
ok - kimi 2.3.0: a root-mcp-json declaration is announced on the folder prompt, which receives no answer, and its command never ran
# kimi 2.3.0: kimi-code-mcp-json prompt announces: Start 1 MCP server automatically;Config: .kimi-code/mcp.json;
ok - kimi 2.3.0: a kimi-code-mcp-json declaration is announced on the folder prompt, which receives no answer, and its command never ran
# kimi 2.3.0: 100x7 pane shows: Trust this folder?;Enlarge terminal to review sources. Esc exit.;
# kimi 2.3.0: 100x12 pane: the announcement is on a hidden page, so only the page marker refuses this prompt
ok - kimi 2.3.0: a short pane collapses the prompt below the complete dialog, and a slightly taller one pages it with the page marker on screen
ok - kimi 2.3.0: folder-prompt predicates agree with the installed Kimi on every recorded wording
```

The portable regression `tests/fm-kimi-harness.test.sh` replays the recorded panes through its fake pane: the plain prompt is answered once and the brief delivered, each announcing wording and the paged prompt receive no key and report why, and the collapsed prompt reports that it is not ready.
Each case is non-vacuous: dropping the 2.3.0 option pair from the complete-dialog test fails the plain case, making the announcement test never fire fails the root `.mcp.json` case, and making the page test never fire fails the paged case.
The 2.0.0 wording keeps its existing cases in the same suite.

## Claude workspace trust

Verified 2026-09-03 on Claude Code 2.1.259.
Claude gates a folder it has never seen behind an interactive workspace-trust dialog, and the CLI documents the only bypass as non-interactive mode, which a crewmate pane is not.

```sh
claude --version
claude --help | grep -A 5 'workspace trust dialog'
```

```
2.1.259 (Claude Code)
                                        pipes). Note: The workspace trust dialog
                                        is skipped when Claude is run in
                                        non-interactive mode (via -p, or when
                                        stdout is not a TTY, e.g. piped or
                                        redirected output). Only use this in
                                        directories you trust. Settings files
```

`--dangerously-skip-permissions` is a permission control and is absent from that bypass, so an interactive worker in a fresh worktree still reaches the dialog.
Firstmate cannot answer it either, because its key plane carries only Enter, Escape, and C-c with no arrow navigation.
Suppression itself was then observed directly on the same date and version, with a control arm and a treatment arm.

The control arm launched a fresh linked worktree with no pre-registration, the way `bin/fm-spawn.sh` launches one.

```sh
tmux new-session -d -s tp-a -c /tmp/trustproof/wt-a \
  "CLAUDE_CONFIG_DIR=<cfg> CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude --dangerously-skip-permissions '<brief>'"
```

```
Accessing workspace: /tmp/trustproof/wt-a
Quick safety check: Is this a project you created or one you trust? ...
Claude Code'll be able to read, edit, and execute files here.
> No, exit
  Yes, I trust this folder
Enter to confirm . Esc to cancel
```

That pane confirms two load-bearing claims at once: the dialog fires despite `--dangerously-skip-permissions`, and the selection cursor sits on `No, exit`, so a sent Enter would have exited the worker.

The treatment arm pre-registered an equivalent fresh worktree and launched it identically against the operator's real config.

```sh
bin/fm-claude-trust.sh /tmp/trustproof/wt-c /tmp/trustproof/proj
tmux new-session -d -s tp-c -c /tmp/trustproof/wt-c \
  "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude --dangerously-skip-permissions 'reply with exactly: BRIEF-REACHED'"
```

```
trusted: /tmp/trustproof/wt-c
```

```
Claude Code v2.1.259 ... /tmp/trustproof/wt-c
> reply with exactly: BRIEF-REACHED
. BRIEF-REACHED
```

No dialog appeared and the worker executed its brief with zero keypresses.
The scratch repo was deleted and the test entries were removed from the store and verified absent.
That verification is point-in-time rather than a durable guarantee, because a concurrent Claude session can re-add a path it visited: one entry reappeared after an earlier zero-residual check, most plausibly flushed by a session as it exited, and was removed again.

One limitation belongs beside that result.
An intermediate arm run against an isolated `CLAUDE_CONFIG_DIR` holding only a copied `.claude.json` cleared the trust dialog but then surfaced the separate machine-scoped Bypass Permissions warning.
That warning rendered in the same shape as the trust dialog, with the selection cursor on `No, exit` and the footer `Enter to confirm . Esc to cancel`, so a sent Enter would end that worker too.
That gate is not a production blocker, because a normal environment has already accepted it and the treatment arm above ran against the real config and saw neither dialog.
This change does not address that warning and does not claim to.

### Secondmate homes

Verified 2026-09-11 on Claude Code 2.1.269.
A secondmate launches in its own firstmate home rather than a task worktree, and that home meets the same gate.
The control arm launched a standalone-clone secondmate home that the store had no entry for, the way `bin/fm-spawn.sh --secondmate` launches one.

```sh
tmux -L <sock> new-session -d -s ctrl -x 180 -y 44 -c <home> \
  "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude --dangerously-skip-permissions"
```

```
 Accessing workspace:
 /private/tmp/fm-sm-trust-live-69759/fm-homes/livemate-n1
 Quick safety check: Is this a project you created or one you trust? ...
 ❯ No, exit
   Yes, I trust this folder
```

The treatment arm pre-registered that same home through the secondmate-home mode and launched it identically against the operator's real config.

```sh
bin/fm-claude-trust.sh --secondmate-home <home> livemate-n1
```

```
trusted: /private/tmp/fm-sm-trust-live-69759/fm-homes/livemate-n1
```

```
 ▐▛███▛█   Claude Code v2.1.269
▝▜██████▀  Opus 4.8 with high effort · Claude Max
  ▝▝ ▝▝    /private/tmp/fm-sm-trust-live-69759/fm-homes/livemate-n1
...
❯
  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents
```

No dialog appeared, the composer was reached, and neither did the machine-scoped bypass warning, because this ran against the real config.
The lab home was deleted and the test entry was removed from the store and verified absent, with the same point-in-time caveat as the worktree arms above.

`bin/fm-spawn.sh` therefore pre-registers the directory every claude launch starts in through `bin/fm-claude-trust.sh` before launch, and `tests/fm-claude-trust.test.sh` pins both halves of the scope contract for both shapes: a fresh worktree and a seeded secondmate home are trusted, and an out-of-scope path is refused.
That automated spawn case runs against a fake claude, so it asserts the store entry and the launch command and nothing more; the live arms above are what establish that the entry actually suppresses the dialog.
The composer-classification record below observes the same gate from the other side, where an untrusted worktree left Claude and Muse unverified because the guard reads a first-launch trust dialog as an unreadable composer.

## Launch-prompt backstop signatures

`bin/fm-busy-lib.sh`'s launch-prompt backstop (`fm_busy_launch_prompt_parked`) reclassifies a launch whose busy record is still pinned at the fm-spawn seed as `unknown launch-prompt`, rather than `busy fm-spawn`, when the captured pane matches that harness's own recognized trust, sign-in, or first-run dialog.
Each signature below was live-verified against the real installed binary through `tests/fm-launch-prompt-signals-live-e2e.test.sh` (`FM_LAUNCH_PROMPT_SIGNALS_LIVE=1`), which is what refreshes this record after an upgrade.

Verified 2026-09-22 on Claude Code 2.1.278 and gemini 0.60.0.

```sh
FM_LAUNCH_PROMPT_SIGNALS_LIVE=1 bash tests/fm-launch-prompt-signals-live-e2e.test.sh
```

```
# live claude version: 2.1.278 (Claude Code)
ok - claude: a real launch parked on its own rendered trust dialog surfaces through the watcher gate
# live gemini version: 0.60.0
ok - gemini: a real launch parked on its own rendered auth or trust dialog surfaces through the watcher gate
```

Claude, launched `--dangerously-skip-permissions` into a brand-new worktree under the operator's own already-onboarded config (the shape a real crewmate spawn produces):

```
 Accessing workspace:

 /tmp/fm-launch-prompt-claude.XXXXXX/wt

 Quick safety check: Is this a project you created or one you trust? (Like your own code, a well-known open source project, or work from your team). If not, take a moment to review what's in this
 folder first.

 Claude Code'll be able to read, edit, and execute files here.

 Security guide

 ❯ No, exit
   Yes, I trust this folder

 Enter to confirm · Esc to cancel
```

Gemini, launched `GEMINI_CLI_TRUST_WORKSPACE=true gemini -y` with no `GEMINI_API_KEY` and no prior OAuth credential:

```
 ? Get started

   How would you like to authenticate for this project?

   ● 1. Sign in with Google
     2. Use Gemini API Key
     3. Vertex AI

   No authentication method selected.

   (Use Enter to select)

   Terms of Services and Privacy Notice for Gemini CLI

   https://geminicli.com/docs/resources/tos-privacy/
```

The real pane renders this inside a bordered box, omitted here for readability; that border is exactly what proves the point below.

That capture demonstrated why each signature function matches the FULL captured tail rather than the Rovo/AGY busy-footer convention of the last 12 non-blank lines: a bordered dialog box renders many short lines of pure border and padding (`│  ...  │`) that are NOT whitespace-only, so the 12-line reduction pushed this exact heading text out of the window and silently defeated the match on the first attempt.
None of these runs ever answered its dialog (Escape only, never Enter), so no credential store was written to and no model tokens were spent.

## Worker account pin sign-in check

`bin/fm-worker-account-lib.sh` decides whether a pinned account is signed in from vendor output: the exit status of `claude auth status`.
`tests/fm-worker-account-live-e2e.test.sh` asks the real installed runner about synthetic roots that need no login and no network, under a throwaway `HOME`.
A Claude root whose `settings.json` names an `apiKeyHelper` reports `loggedIn: true`.
Each refusal is paired with the divergence it depends on: the same runner, given `ANTHROPIC_API_KEY`, answers signed in for the empty root, so the refusal proves the check's cleared environment.
Replacing `env -i` with `env` in the check makes the guard fail on the Claude refusal.

Verified 2026-09-22 on Claude Code 2.1.278 on Linux.

```sh
bash tests/fm-worker-account-live-e2e.test.sh
```

```
ok - claude 2.1.278 (Claude Code): the pin check accepts a signed-in root and refuses an empty one despite an ambient API key
```

The guard submits no prompt and spends no tokens, so it runs by default wherever a runner is installed; rerun it after every Claude upgrade.

## Claude worker tool exclusions

`config/crew-exclude-tools` reaches a Claude ship or scout launch as `--disallowedTools '<names>'` placed directly before `--append-system-prompt`, because the option is variadic and would otherwise swallow the launch prompt.
[Worker tool exclusions](../configuration.md#worker-tool-exclusions-configcrew-exclude-tools) owns the contract; this record owns the measurement.
Verified on 2026-11-06 with Claude Code 2.1.319 on Linux, interactive launches in a tmux pane with tool search on, against a capture-only local server (`ANTHROPIC_BASE_URL`) that records each `/v1/messages` body and answers 529, so no model is called.
The arms differ only in the `--disallowedTools` value; the figures are the bytes of the JSON `tools` array and of the whole request for the main-agent request. The two repeats of the `Workflow,Artifact,mcp__claude-artifacts` arm matched on tool schema bytes and differed by 12 request bytes.

| Launch | Tools sent | Tool schema bytes | Request bytes |
| --- | --- | --- | --- |
| no list, artifacts MCP server connected | 20 | 52064 | 188189 |
| `Workflow,Artifact,mcp__claude-artifacts` | 12 | 28416 | 161748 |
| `mcp__claude-artifacts` only (built-in `Artifact` takes its place) | 14 | 70987 | 206684 |
| `Workflow,Artifact,mcp__claude-artifacts` | 12 | 28416 | 161736 |

Findings that shape the contract:

- A disallowed name is removed from the request's `tools` array, and a disallowed deferred MCP tool's name also leaves the deferred-tool list in the messages, so the saving is not only the schema.
- `--tools` is not a substitute: naming an allow-list made Claude Code send every connected MCP tool eagerly (65 tools, 139760 schema bytes in the same environment), the opposite of a saving.
- A server-level entry `mcp__<server>` hides every tool of that server, and with the artifacts server hidden Claude Code supplies a 37098-byte built-in `Artifact` tool, so both names are needed to drop every artifact schema.

The token-free live guard refreshes the per-version evidence and fails naming the Claude Code version if a release stops honoring the flag:

```sh
bin/fm-test-run.sh tests/fm-claude-tool-exclude-live.test.sh
```

## Secondmate busy contract

Verified 2026-09-22 on this host with Claude Code 2.1.278 and OpenCode 1.18.31.

A tmux-backed secondmate's active-turn gate reads the parent home's semantic busy record.
An opencode launch arms that record and loads the same plugin an ordinary worker uses, and that plugin does not touch the parent's turn-ended marker.
A Claude secondmate arms the same record through busy hooks in the parent home's `state/<id>.claude-settings.json`, passed as Claude Code's `--settings` file, and does not write the mate home's `.claude/settings.local.json`.
That `--settings` load and the merge of its hook entries with the home's own hooks rest on Claude Code's documentation (<https://code.claude.com/docs/en/cli-reference>, <https://code.claude.com/docs/en/hooks>) and not on a live run recorded in this section: the sample output below predates the `--settings` mechanism.
A Claude secondmate is the one exception on Stop: its home's tracked Stop guard is the only Stop writer, recording idle when it allows the Stop and busy when it blocks it into a continuation, because Claude runs Stop hooks in parallel.
Claude Code 2.1.278 was probed live in a scratch project with logging `UserPromptSubmit` and `Stop` hooks.
A synchronous Stop hook that exits 2 forced a continuation with no `UserPromptSubmit`, which is why the guard itself records busy when it blocks.
An `asyncRewake` Stop hook that exited 2 six seconds after the turn ended woke a new turn, and `UserPromptSubmit` fired 45ms after that hook exited.
So a secondmate turn started by the Stop auto-arm reopens busy through the same `UserPromptSubmit` hook as a typed prompt, and the auto-arm needs no busy writer of its own.

```text
# asyncRewake probe                # synchronous block probe
ups    1790092380.194370578        ups   1790092417.676751768
stop   1790092380.968402195        stop  1790092418.684176531
rewake 1790092386.979819188        block 1790092418.692480013
ups    1790092387.025050498        stop  1790092419.717886938
stop   1790092388.953108486
```
Codex stays unverified.
Cursor's transcript sidecar is written for a secondmate the same way it is for an ordinary worker, and this host has no Cursor agent binary, so that path was not started.
Kimi stays unarmed, and a secondmate still gets no parent turn-end token.

The portable regression is `tests/fm-busy-adapter-wiring.test.sh`.
It spawns those harnesses through the real `bin/fm-spawn.sh --secondmate` path on a fake tmux pane, drives the generated hook or extension, and runs the stall gate while the record is busy and again after it goes idle.

The live guard is `tests/fm-secondmate-busy-contract-live-e2e.test.sh`.
It runs by default wherever tmux is installed.
`FM_SECONDMATE_BUSY_LIVE=1` forces an absent binary to fail rather than skip.
The spawn pane is a sleeper, so the launch brief is never delivered to a model.
Each installed armed harness is then started for real, with no prompt and no keystrokes.

```sh
bash tests/fm-secondmate-busy-contract-live-e2e.test.sh
```

```text
# claude 2.1.278 (Claude Code): real process stayed up; pane tail classify=busy fm-spawn
ok - claude 2.1.278 (Claude Code): a tmux secondmate spawn arms a busy verdict the active-turn gate can see
# opencode 1.18.31: real process stayed up; pane tail classify=busy fm-spawn
ok - opencode 1.18.31: a tmux secondmate spawn arms a busy verdict the active-turn gate can see
# pi 0.86.1: real process stayed up; pane tail classify=unknown launch-prompt
ok - pi 0.86.1: a tmux secondmate spawn arms a busy verdict the active-turn gate can see
# skip: pi-signed is not installed on this machine, so its secondmate busy contract is unverified here
# skip: omp is not installed on this machine, so its secondmate busy contract is unverified here
ok - grok grok 1.0.40 (eb1a2256660d) [stable]: secondmate spawn stays unarmed and does not emit a parent turn-end
# skip: codex is not installed on this machine, so its secondmate busy contract is unverified here
# checked 4 harness(es); absent: pi-signed omp codex
ok - secondmate busy contract live guard checked every installed harness
```

## Codex hook trust

Verified 2026-09-16 on codex-cli 0.151.0, macOS arm64, in a fresh linked worktree of this repository.

Codex gates hooks it has no persisted trust for behind an interactive modal.
A crewmate launch built by `bin/fm-spawn.sh` was driven under a real PTY and stopped there before the brief was ever submitted:

```text
Hooks need review
12 hooks are new or changed.
Hooks can run outside the sandbox after you trust them.
> 1. Review hooks
  2. Trust all and continue
  3. Continue without trusting (hooks won't run)
Press enter to confirm or esc to go back
```

The selection starts on "Review hooks", which is neither trusting nor declining, and Firstmate's key plane carries only Enter, Escape, and C-c with no arrow navigation, so the selection cannot be moved.
That count covers every hook Codex had no persisted trust for, drawn from both the machine's own `~/.codex/hooks.json` and this repository's tracked `.codex/hooks.json`.
Writing Codex's own trust store to pre-accept the modal would record an operator consent that was never given, so it is not an option either.

`codex --help` documents `--dangerously-bypass-hook-trust` as "Run enabled hooks without requiring persisted hook trust for this invocation", which RUNS the untrusted hooks.
That is the opposite of what an unattended worker needs, so the control used is the hook feature flag:

```sh
codex features list | grep '^hooks'
codex --disable hooks features list | grep '^hooks'
codex --disable no_such_feature features list
```

```text
hooks                                    stable             true
hooks                                    stable             false
Error: Unknown feature flag: no_such_feature
```

The last arm is what makes the requested control safe to depend on: an unknown feature name is a hard error, so a release that renames or drops the flag stops the launch rather than silently restoring the modal.
A managed policy can still override the requested disablement, so the effective hook state is not a portable guarantee.

The same launch with the hook disablement requested reached the composer with no modal, answered the prompt, and fired the turn-end program that rides the launch rather than any hook:

```sh
codex --dangerously-bypass-approvals-and-sandbox --disable hooks \
  -c "notify=[\"bash\",\"-c\",\"touch $TURNEND\"]" "Say ACK and stop."
```

```text
> Say ACK and stop.
- ACK, captain.
$ ls "$TURNEND"
<turn-end file present>
```

`tests/fm-codex-hook-layer-live-e2e.test.sh` checks current flag acceptance; it does not repeat the composer and notification probe above.
It captures the launch `bin/fm-spawn.sh` actually builds and confirms that the installed Codex accepts the requested hook-disablement flag.
It does not claim that a managed policy cannot re-enable hooks after launch.
The portable half, `tests/fm-spawn-dispatch-profile.test.sh`, pins the requested hook-disablement flag for crewmates and its omission for secondmates, which run primary sessions on this repository's own project hooks.

### Stop response parsing

Verified 2026-11-03 on Linux x86_64 with codex-cli 0.162.1.
The existing live hook-layer guard exercises the installed app-server's `hook/completed` notifications against a loopback Responses fixture that returns fixed text and no tool calls.
Each app-server has isolated config, hook trust, login files, and data; it neither uses a shared daemon nor contacts a model provider.
The fixture trusts only its synthetic Stop handler's exact key/hash.

```sh
bash bin/fm-test-run.sh --jobs 1 tests/fm-turnend-guard.test.sh tests/fm-codex-hook-layer-live-e2e.test.sh
```

```text
ok - .codex Stop wrapper: clean success JSON, inherited PATH, unchanged errors and continuation without logout output
ok - codex codex-cli 0.162.1: Stop parser checked 12 isolated cases with clean wrapper JSON and bounded continuation
FM_TEST_SUMMARY total=2 failed=0 skipped_gate=0 duration_ms=97428
```

The portable regression makes its login-shell logout emit terminal escape bytes and confirms that the fixture is effective before checking the tracked command's actual output.
It also checks primary, child-worktree, and non-Firstmate scope, empty input, missing jq, malformed registration, a non-executable guard, inherited PATH, and unchanged error status/stderr.
The optional native park's synchronous guard dispatch preserves its `--guard` argument, original payload, success JSON, and exit-2 stderr in an isolated executable fixture without registering a park.
The live parser accepts both empty output and `{}`, rejects mixed diagnostics/JSON, malformed syntax, multiple objects, and a wrong field type, and preserves an ordinary nonzero error.
The real copied supervision guard blocks once with its stderr reason, then allows the continuation's Stop; the fixture asserts both native hook verdicts and the two-request bound.
These checks refresh the Codex adapter evidence; [the integration owner](../turnend-guard.md#harness-integrations) describes its current behavior.

## Codex automatic approval review

Verified 2026-10-06 with codex-cli 0.160.1.
`codex --help` describes `--approve-for-me` as `Route approval requests through automatic review using the workspace-write sandbox`.
A managed-settings reproduction showed that `--dangerously-bypass-approvals-and-sandbox --disable hooks` could leave user-reviewed approvals active even while the sandbox bypass applied.
Replacing that flag with `--approve-for-me --disable hooks` selected automatic approval review and the workspace-write sandbox.

A real worker in that posture appended its authorized Firstmate status channel, inspected its steering channel, queried the no-mistakes service, completed `git push --dry-run`, and completed a GitHub read.
The networked operations initially required automatic review because the workspace-write sandbox begins with network access disabled, then completed after that review.
This confirms unattended progress through the reviewer, not unrestricted network or external-write access.

`tests/fm-spawn-dispatch-profile.test.sh` pins unchanged bypass defaults and explicit `approve-for-me` launches for ships and scouts, plus hook and secondmate launch wiring.
`tests/fm-approval-failover.test.sh` exercises the firstmate-invoked command through real filesystem publication and the existing lease owner, substituting lifecycle control to avoid touching real workers.
It covers writing once, preserving explicit and concurrent settings, invoking guarded relaunch, retaining the remedy on recovery failure, and local/remote inheritance precedence.
These behavior tests do not verify an actual vendor-refusal recovery or live relaunch; the prior live automatic-review probe verifies the fallback's capabilities, not that complete recovery path.
There is no automatic detector or harness-output classifier to verify, and a generic login error does not establish a defeated bypass.

## Composer classification matrix

The shared composer classifier (`bin/fm-composer-lib.sh`, `fm_composer_classify_screen`) owns every composer shape fleet-wide; each backend contributes only a capture and a capability descriptor.
The live half of that guarantee was verified on 2026-08-10 from an already-trusted checkout at the branch's final validated head, against every installed harness then covered by the empty-composer matrix on tmux 3.6a, macOS arm64, on an isolated private socket, with no prompt submitted to any harness.
An earlier untrusted-worktree run left Claude and Muse unverified because the guard treats first-launch trust dialogs as an unreadable-composer state and never confirms them; this trusted-checkout rerun supersedes those missing results.

```sh
FM_COMPOSER_MATRIX_LIVE=1 tests/fm-composer-matrix-live-e2e.test.sh
```

Observed output:

```text
ok - claude (2.1.227 (Claude Code)): real idle composer classifies empty
ok - codex (codex-cli 0.146.0): real idle composer classifies empty
ok - opencode (1.14.46): real idle composer classifies empty
ok - pi (0.84.0): real idle composer classifies empty
ok - grok (grok 1.0.0 (3cd0d0cbcebe)): real idle composer classifies empty
# harness absent, not verified here: kimi
ok - muse (Muse Code 0.1.0 (0.1.0-R708.1)): real idle composer classifies empty
ok - strict posture live: a blank shell row classifies unknown and injection defers
ok - zellij (zellij 0.44.0): unrelated pane change never confirms delivery (verdict: unknown)
ok - live composer-matrix guard verified 8 live surface(s)
```

All six installed harnesses' real idle composers reached a proven `empty` (Claude auto-updated to 2.1.227 between the audit and this rerun, so the shipped classifier is proven against the newer release as well), including OpenCode through the left-bar shape; Codex and OpenCode first parked on vendor update-available modals that the strict classifier correctly refused until the guard's single non-submitting Escape dismissed them.
The strict blank-row posture held live (a blank shell row deferred injection), and a zellij pane changing for reasons unrelated to submission never confirmed a delivery, replacing the retired content-diff heuristic's false positive.
Kimi was not installed on the verification machine; its bordered shape is pinned by the portable byte-capture regressions in `tests/fm-composer-lib.test.sh`, which also carry the other five adapters' capability profiles for every harness under both a UTF-8 locale and `LC_ALL=C`.
This guard is the refresh command after an upgrade to any matrix-covered harness; rerun it and update the versions above rather than trusting this table across releases.
Cursor is deliberately outside this cursor-anchored empty-composer matrix because its terminal cursor is parked outside the composer; tmux's Cursor-specific, process-identity-gated cursorless fallback is covered by the [Cursor Agent CLI](#cursor-agent-cli) section's separate live evidence and drift guard.

### 2026-10-14 opencode 1.19.0 de-emphasised mode/footer row in the left-bar composer

Verified on 2026-10-14 on macOS arm64 against an installed opencode 1.19.0 running as a Firstmate worker in a tmux 3.6a pane, read through `fm_tmux_composer_state` (`bin/fm-tmux-lib.sh`) with the tmux capability descriptor (`styled=1`, `cursor=1`, `identity=1`, `rows=0`).
Every message the fleet tried to send and every worker restart or shutdown was refused, because the composer verdict authorizing typing was `pending` on a composer that was empty.

Opencode's left-bar composer draws its mode/model/branch line INSIDE the box as its last row, and that row's identifying cells are DE-EMPHASISED: the mode word is `ESC[38;2;67;133;190m` (luminance 119.8) and the middle-dot separators are `ESC[38;2;111;110;105m` (luminance 109.7), both under `FM_COMPOSER_GHOST_LUMA_MAX`'s 128, while the model, effort, and branch cells beside them are bright.
`fm_composer_strip_ghost` exists to answer "what did the human type?", so it deleted precisely the cells that identify the footer, and the row reached `_fm_composer_classify_leftbar` opening at the bright model cell (`Space Bunny max fm-composer-footer` on the pane above, `Grok 4.7 ... tt-record-refresh` on the pane the incident was recorded from) instead of at `Build`.
`FM_COMPOSER_LEFTBAR_FOOTER_RE_DEFAULT`'s `^(Build|Plan)` anchor therefore could not match on ANY styled backend - tmux and Herdr both pass `styled=1`, which is every backend except orca - so the exemption was unreachable and a real idle composer read `pending`.
`pending` is the one verdict that blocks a steer: `fm_task_inbox_ring` defers on it and `bin/fm-watch.sh`'s re-ring calls the same function, and `bin/fm-send.sh` and `bin/fm-control.sh` refuse it, so the measured cost was three manual interventions into worker panes in one day.
The geometry was never at fault: the pane's floor row is still `╹` + `▀` and `_fm_composer_leftbar_floor_row` still recognizes it, and the run's LAST row was correctly the footer row.

`_fm_composer_row_is_leftbar_footer` now proves the footer from BOTH forms of that row, the ghost-stripped content and the ANSI-stripped plain row, because the second is the only form that still carries opencode's own de-emphasised mode cell.
The plain form can only newly exempt a row the ghost-stripped row still fails, which means its stripped content is non-empty while its own leading `Build`/`Plan` cell was stripped as ghost, and opencode de-emphasises its own furniture rather than a typed row's leading cells - so the only rows it admits are de-emphasised furniture, and the mode footer is the only furniture opencode draws that opens with a mode word. That is what makes the exemption self-confirming, and it is the argument to recheck when a new opencode release moves a colour.

The live half is `tests/fm-composer-matrix-live-e2e.test.sh`, run against the same branch before and after the change; only the opencode arm is claimed here, and its `pending`-to-`empty` transition is the whole result:

```sh
FM_COMPOSER_MATRIX_LIVE=1 tests/fm-composer-matrix-live-e2e.test.sh
```

```text
before: not ok - opencode (1.19.0): idle composer never classified empty (last verdict: pending)
after:  ok - opencode (1.19.0): real idle composer classifies empty
        ok - opencode (1.19.0): the same idle pane read cursorless is not pending (verdict: unknown)
```

The same guard failure appears in BOTH runs and is the documented environmental one, not this change's: `claude` 2.1.287 parks on its first-run theme picker, which the guard's header states it correctly refuses to confirm.
Codex, Kimi, and Muse were not installed, so they were reported absent rather than verified.
The cursorless arm is the one that matters for the doorbell, because it is the arm that refuses the skipping verdict: on the recorded live pane it read `unknown`, which defers, and not `pending`. That verdict is not the footer exemption doing the work - a cursorless read selects the bottom-most shape on the screen instead of the cursor-anchored run, so whatever opencode draws below the composer's floor row decides it, and on this record's capture, which keeps only the composer, the same pane read cursorless reaches the same run and reads `empty`.

The portable half lives in `test_matrix_opencode_leftbar_signals` in `tests/fm-composer-lib.test.sh`, carrying the live row's foreground truecolor triples byte for byte in both states: the idle pane reads `empty` on tmux and on Herdr, while a bright `fix the doorbell skip` input row above the same footer reads `pending` on tmux and on Herdr; every one of those assertions is re-run under `LC_ALL=C`.
The same bytes on a plain backend read `unknown` in both states, because opencode 1.19.0 also draws a de-emphasised `~/.treehouse/fm001-b8697d/1/fm001:fm/` row inside the box that survives an unstyled capture, so the strict posture keeps deferring rather than reading `empty` there.
Overriding `FM_COMPOSER_LEFTBAR_FOOTER_RE` to a pattern that cannot match puts the false `pending` straight back on the captured idle pane, which pins the exemption as the load-bearing signal rather than an incidental pass.
`fm_composer_extract_selected_content` applies the same rule to the same run, so the classified-empty pane hands back no composer text and the typed pane hands back only `fix the doorbell skip`.

### 2026-09-20 claude 2.1.236 statusLine footer through Herdr

Verified on 2026-09-20 on macOS arm64 (Darwin 25.6.0) against Claude Code 2.1.236 running as Firstmate workers in Herdr 0.8.0 panes, read through Herdr's ANSI capture with its exact capability descriptor (`styled=1`, `cursor=0`, `identity=1`, `rows=20`).
Claude 2.x draws its composer as a bare `❯` + U+00A0 row between two solid `─` rules, and this home's configured statusLine plus Claude's permission-mode hint render on the two rows directly below the closing rule.
The statusLine's first glyph is `→` (U+2192), which is Cursor's own prompt glyph, so the cursorless "bottom-most shape wins" rule selected the statusLine as a bare composer at `kind=bare first=18 last=19` within the 20-row tail, read the statusLine and the hint row as wrapped typed input, and answered `pending` on a composer holding nothing.
`fm_task_inbox_ring` (`bin/fm-task-inbox-lib.sh`) defers on exactly that verdict, and `bin/fm-watch.sh`'s re-ring calls the same function, so both the first doorbell and every retry were skipped and the worker never saw the steer.

The capture is a read-only `herdr pane read <pane> --source recent --format ansi` of five live worker panes; each 20-row tail is fed to the shared classifier with the descriptor above, resolving the lazy identity sentinel with the pane's real `claude<TAB>idle` identity:

```sh
herdr --session default pane read w83:p2 --source recent --lines 200 --format ansi > claude-2.1.236-idle-herdr.ansi
bash -c '. bin/fm-composer-lib.sh
  caps=$(printf "styled=1\ncursor=0\nidentity=1\nrows=20")
  cap=$(tail -n 20 claude-2.1.236-idle-herdr.ansi)
  v=$(fm_composer_classify_screen "$caps" "$cap")
  [ "$v" != need-identity ] || v=$(fm_composer_classify_screen "$caps" "$cap" "" "$(printf "claude\tidle")")
  printf "%s\n" "$v"'
```

Observed output across the five live panes before the fix and then after it, in pane order `w83:p2`, `w84:p2`, `w87:p2`, `w7R:p2`, `w7W:p2`:

```text
pending pending pending pending pending
empty   empty   empty   pending pending
```

Three of the five composers were genuinely empty and every one of them was refused; the two that stayed `pending` after the fix really did hold text, and the extracted content names it exactly (`<65;77;27M` and `<65;77;27M5;77;27M`, stray SGR mouse reports left in the composer by a click in the pane).
That extraction is the disconfirming measurement: before the fix the extracted "pending text" for an empty composer was the statusLine itself (`bloomandhuda26 git:(...)× | Opus 5 (1M context) | ctx [█░░░░░░] 15% | ... ⏵⏵ bypass permissions on (shift+tab to cycle) · ← 1 agent`), never anything from the composer row, so the pane was never the disagreement - the judgement of it was.
The same panes accepted `fm_backend_send_text_submit` at the same moment because herdr's submit core confirms delivery from native `agent get` state and only falls back to the composer verdict when that state stays idle, so the working path never asked the question the doorbell's pre-send gate asks.

`test_matrix_claude_arrow_statusline_footer` in `tests/fm-composer-lib.test.sh` carries the shape with its statusLine and hint rows, and pins the two protections the fix must not remove: real unsubmitted text in that same composer under that same statusLine still reads `pending`, and so does the stray mouse report.
`test_composer_footer_demotion_needs_a_proven_pair` pins the three bounds of the demotion - a blank row ends the footer zone, a separator pair that closed over no agent-glyph row demotes nothing, and Cursor's half-block-bounded `→` composer is untouched - plus the strict posture that an unanchored statusLine row alone never proves an empty composer.
The footer zone is a property of any envelope a glyph row inside it proves, not of the separator pair specifically, so the same statusLine footer under claude's BORDERED composer (the shape a wide pane renders) is demoted identically; `test_composer_footer_zone_is_shape_independent` carries that box shape, asserts the statusLine is never the extracted composer content, and pins both counterweights - typed text inside that same box under that same footer still reads `pending`, and codex's startup banner, which holds no glyph row and therefore proves nothing, still yields to the live bare row drawn contiguously below it.

The demotion is deliberately ASYMMETRIC: `empty` is the only verdict that authorizes `fm-send` to type into a pane, so the rule may move a verdict toward refusing but never toward `empty`.
It therefore counts a footer zone only when every row in it is demonstrably furniture - a braille animation row, claude's permission-mode hint row (`⏵⏵ bypass permissions on`), or a row leading with an agent glyph OTHER than the one that proved the envelope, which is what the `→` statusLine is on a `❯` claude pane.
A run containing unclaimed activity (`Working on request...`, `→ ran npm test (3 failures)`) is not furniture in either row order and keeps invalidating the envelope above it, and a row leading with the SAME glyph the envelope was proven by (`❯ my typed draft`) is a live composer that keeps winning, so a visible draft is never overwritten.
The one exception, the selected row of Claude 2.1.291's slash-command popup, which leads with that same `❯`, is recorded in [Claude Code 2.1.291 marks the popup's selected row](#claude-code-21291-marks-the-popups-selected-row).
`test_composer_footer_zone_refuses_rather_than_allows` pins both directions on the bordered-box and separator-pair shapes.

Coverage is the bordered box and the separator pair, the two shapes claude 2.x renders. The opencode left bar is wired into the same rule but is **unexercised**: every left-bar row this repo records leads with plain text, and opencode's own prompt character is `>`, a shell glyph deliberately outside the agent set, so no opencode shape recorded here can prove a left-bar envelope or open a footer zone beneath one.

The live refresh for this entry is the cursorless arm added to the composer-matrix guard, which re-reads each harness's already-proven-idle pane the way every non-tmux backend reads it and fails naming the harness and version when that read is `pending`:

```sh
FM_COMPOSER_MATRIX_LIVE=1 tests/fm-composer-matrix-live-e2e.test.sh
```

On 2026-09-20 that guard could not reach its new arm for either installed harness, and the same failures reproduce on the unmodified library: bare `claude` 2.1.236 opens the session picker rather than a session, and the guard's mid-budget Escape then quits it, while codex-cli 0.147.0 parks on a hooks-trust modal the guard correctly refuses to confirm.
The Herdr captures above are therefore this entry's live evidence, and the guard's claude arm owes a separate repair before it can refresh it.

### 2026-09-29 claude 2.1.284 named session through Herdr

Verified on 2026-09-29 on Linux x86_64 against Claude Code 2.1.284 in Herdr 0.9.1 panes of an isolated lab session, read through `fm_backend_composer_state herdr <session>:<pane>` with the adapter's real capture and identity probe.
A session started as `claude -n <name>` right-aligns that name in the rule above the composer (`───…─── <name> ─`), while the rule below stays solid.
Herdr supplies no cursor, and the cursorless scan accepted only solid rules, so it recorded the lower rule alone; a lone rule below the `❯` row made cursorless selection refuse, and the idle composer read `unknown`.
`inject_msg` in `bin/fm-supervise-daemon.sh` defers on anything but `empty`, so every away-mode escalation to a named Claude primary on Herdr deferred until the captain returned, without typing anything or writing its operational record.
The same named pane read `empty` on tmux, where the cursor row anchors the bare `❯` composer directly.

Before the fix, one variable at a time on idle panes:

```text
claude                                                      herdr: empty
claude -n <name>                                            herdr: unknown
CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude -n <name> herdr: unknown
claude -n <name>                                            tmux:  empty (typed text: pending)
```

The classifier now accepts a bare agent-glyph row sandwiched between a width-proven titled top rule and its solid closing rule (`_fm_composer_titled_rule_row` and `_fm_composer_bare_rule_sandwich` in `bin/fm-composer-lib.sh`, issues #5601 and #5558).
After the fix the named Herdr pane read `empty`, and the daemon's real injection path wrote the operational record, typed the doorbell, sent Enter, and confirmed the submit on that pane.
`test_matrix_claude_named_session_titled_rule` in `tests/fm-composer-lib.test.sh` pins idle, ghost-suggestion, typed, and extraction cases on every capability profile, and the unnamed ghost case.
The composer-matrix guard's `claude-named` arm requires the cursorless read of a real named Claude pane to be exactly `empty`:

```sh
FM_COMPOSER_MATRIX_LIVE=1 tests/fm-composer-matrix-live-e2e.test.sh
```

```text
ok - claude-named (2.1.284 (Claude Code)): real idle composer classifies empty
ok - claude-named (2.1.284 (Claude Code)): the same idle pane read cursorless is not pending (verdict: empty)
```

### 2026-09-15 codex-cli 0.154.0 idle starfield and status footer through Herdr

Verified on 2026-09-15 on macOS arm64 (Darwin 25.5.0) against codex-cli 0.154.0 (model gpt-6-astra, fast mode) running as a Codex second mate inside a Herdr pane, read through Herdr's ANSI capture with its exact capability descriptor (`styled=1`, `cursor=0`, `identity=1`, `rows=20`).
Idle, codex 0.154 animates a braille starfield on the row above its bold `›` prompt row, on the `›` row behind the SGR-2 dim `Ask Codex to do anything` placeholder, and on the row below it, then draws a status footer reading `gpt-6-astra high fast · ~/Projects/purser · Launch Purser desk brief`.
The starfield cells are truecolor greys whose luminance runs from roughly 66 to 165, so the cells above the 128 ghost ceiling survive ghost stripping, and the footer is bright, non-blank, and carries no structural edge.

The capture is a read-only `herdr pane read <pane> --format ansi` of the live pane; its 20-row tail is fed to the shared classifier with the descriptor above:

```sh
herdr pane read w4Z:p2 --format ansi > codex-0.154-idle-herdr.ansi
bash -c '. bin/fm-composer-lib.sh
  caps=$(printf "styled=1\ncursor=0\nidentity=1\nrows=20")
  fm_composer_classify_screen "$caps" "$(tail -n 20 codex-0.154-idle-herdr.ansi)"'
```

Observed output on the same capture before the fix (`bin/fm-composer-lib.sh` at b85e28b5) and then after it:

```text
pending
empty
```

Before the fix the bare `›` shape extended its wrap region over the two rows beneath the glyph (`kind=bare first=17 last=19` within the 20-row tail), read the surviving starfield cells and the footer as wrapped typed input, and answered `pending`.
The steering doorbell (`fm_task_inbox_ring` in `bin/fm-task-inbox-lib.sh`) defers on exactly that verdict, so every ring for the pane was recorded as skipped and the marked request was reported as a missed delivery.
After the fix, braille-only rows bound the wrap region (the status footer sits beneath the starfield row, so the region never reaches it), starfield cells behind the placeholder are stripped from the glyph row, and the same capture reads `empty` under the Herdr styled profile and with a tmux cursor on the glyph row, while a plain (`styled=0`) capture still reads `unknown`, never `pending`.
A second read-only capture of the same pane, taken during the fix with a bright starfield cell drawn between the `›` and the placeholder, read `pending` before and `empty` after as well.
`test_matrix_codex_idle_starfield_furniture` in `tests/fm-composer-lib.test.sh` carries both samples byte-for-byte, the divergence (the same screen with letters in place of the starfield reads `pending`), and the over-stripping negatives (wrapped typed input, braille mixed with text, a typed row with a middle dot, and the footer or a starfield row alone).

The live guard that refreshes this entry launches the installed codex idle in an isolated tmux server and asserts `empty` through both the cursor-anchored tmux read and the cursorless styled read Herdr uses, naming codex and `codex --version` on failure; it is default-on wherever codex and tmux are installed and spends no tokens:

```sh
tests/fm-composer-codex-idle-live-e2e.test.sh
```

The verification machine runs its fleet on Herdr and has no tmux installed, so on 2026-09-15 that guard reported `skip: live: tmux absent` there, and the Herdr capture above is this entry's live evidence.
The guard also notes whether the starfield and the placeholder were actually drawn during its read, because codex need not animate them under every model or mode; a refresh on a tmux host should record that note beside the verdict rather than assume the starfield was exercised.

### 2026-09-18 OpenCode 1.18.31 idle cwd:branch furniture through tmux

Verified on 2026-09-18 on macOS arm64 (Darwin 25.5.0) against OpenCode 1.18.31 running as eight idle firstmate tmux workers in this home (the fm-deck-* panes of tmux session 0, 272x70), read through the tmux adapter's real styled capture and cursor row.
Idle, the left-bar composer holds no hint row: the pane's working directory and branch are drawn right-aligned inside the composer rows above the Build footer, wrapped over up to three rail-width fragments beginning near column 233 of 272 whose final fragment is drawn at the right end of the footer row itself, for this machine the string `~/.treehouse/harness-engineering-presentation-a32ea0/7/harness-engineering-presentation:fm/deck-07-failure-modes`.
The fragments are truecolor RGB 128,128,128 whose luminance is exactly 128, so they sit ON `FM_COMPOSER_GHOST_LUMA_MAX` and survive ghost stripping; blanking the below-floor path and footer rows did not change the earlier verdict, so the right-aligned fragments inside the composer rows were the whole cause.
The furniture is not a 1.18.31 layout change: upstream anomalyco/opencode#36457 (merged 2026-07-11) added it, every 1.18.x tag carries it, and the rendering block is byte-identical at the v1.18.4 and v1.18.31 tags apart from a spacer commit.
It is drawn whenever the pane has an active session and no higher-priority footer hint (workspace label, move progress, notice, or a custom hint), so the defect affects every OpenCode 1.18.x tmux worker from its first turn onward, not only this fleet and not only 1.18.31 (verified against the upstream source at those tags on 2026-09-20).

The previous read treated those fragments as unsent typed text, so `fm_tmux_composer_state` answered `pending` for every idle 1.18.31 worker, which skipped `fm-send`'s doorbell, the watcher's re-ring ladder, and `bin/fm-control.sh` exit/relaunch typing.
Read-only, using one idle worker pane:

```sh
fm_tmux_composer_state 0:fm-deck-07-failure-modes
```

Observed output on the same pane before the fix and after it:

```text
pending
empty
```

The same verdict held on deck-01 and deck-02 after the fix, and the byte-captured 20-row tail with its real `#{cursor_y}` is carried in `tests/fixtures/opencode-1.18.31-cwd/opencode-1.18.31-idle-cwd.ansi`.
The same day, the idle pane `0:fm-anvil-backlog-docs-hygiene` (272x70, `#{cursor_y}` 64) showed that a cwd:branch shorter than the rail wraps BOTTOM-aligned: its two upper composer rows were blank rail, the single fragment `~/.treehouse/anvil-99d6f9/2/anvil:fm/` sat directly above the footer row, and the footer row's right end carried `anvil-backlog-docs-hygiene`; that read-only capture is `tests/fixtures/opencode-1.18.31-cwd/opencode-1.18.31-idle-short-cwd.ansi` and answers `empty` too.
`test_matrix_opencode_leftbar_cwd_furniture` in `tests/fm-composer-lib.test.sh` asserts `empty` on both fixtures with the cursor anchored inside the furniture and on the cropped cursorless profiles, a left-edge typed line (prose and a path-shaped string alike) staying `pending`, and a right-aligned fragment that is not part of a `path[:branch]` staying typed.
`_fm_composer_leftbar_cwd_start` in `bin/fm-composer-lib.sh` recognises the run structurally - contiguous single-token rows immediately above the footer row whose gap after the bar exceeds half the region's width (the widest trimmed plain row across the region), whose TOPMOST fragment itself begins with `~/` or is an absolute path with a name after its leading slash, and whose fragments carry no whitespace - so a wrong call defers except the accepted residual: a lone whitespace-free path token typed so far right that its text starts beyond the region's midpoint in an otherwise empty composer; position, not shape alone, still decides.
The path start is checked on that top fragment's own bytes rather than on the concatenation, so a typed lone `~` directly above the rail stays an ordinary typed row.
A lone `/` (or a slash-only token) is deliberately not accepted, because a composer holding only `/` is the first keystroke of a slash command and must never read `empty`; a typed slash command such as `/exit` starts at the left edge and fails the position gate.
The footer row itself, tail fragment included, stays furniture through the existing last-row footer regex and is not read by the recognition.

### 2026-10-14 OpenCode 1.18.31 absolute cwd rail on a wide tmux pane

Verified on 2026-10-14 on Linux against OpenCode 1.18.31 tmux workers whose worktrees live under an absolute path outside `$HOME` (308-column panes), busy and idle alike.
The rail's first fragment is an absolute path (`/...`) drawn right-aligned on the composer row above the Build footer, and the `~/`-only start rule read every such worker `pending`, skipping the doorbell and refusing `bin/fm-control.sh` exit and relaunch.
Busy and idle read the same because the left-bar region ends at the composer's floor row and the `esc interrupt` status line below it is never examined.
The sanitized 20-row busy capture (cursor row 14 in the tail) and its idle twin are `tests/fixtures/opencode-1.18.31-cwd/opencode-1.18.31-busy-wide-abs-cwd.ansi` and `opencode-1.18.31-idle-wide-abs-cwd.ansi`; `test_matrix_opencode_leftbar_abs_cwd_furniture` asserts `empty` on both, `pending` for a right-aligned lone `/`, `/exit` and an absolute path typed at the left edge, and typed text above the rail, and that extraction excludes the rail fragment.
The opt-in live check runs OpenCode in a wide pane under `/tmp` and asserts `empty` mid-turn and idle:

```sh
FM_OPENCODE_ABS_CWD_LIVE=1 bash tests/fm-opencode-abs-cwd-rail-live-e2e.test.sh
```

Observed output with the widening, and the mid-turn verdict with the `~/`-only rule:

```text
ok - opencode mid-turn absolute cwd rail on a 300-column pane reads empty
ok - opencode idle absolute cwd rail on a 300-column pane reads empty
not ok - mid-turn absolute cwd rail read 'pending', want empty
```

The cursorless backends still defer: on a cursorless read (Herdr) a full-pane capture of this version answers `unknown` because the status rail below the composer floor row is contiguous non-blank content the selector refuses to outrank, which is the strict posture and not this defect; and very narrow panes where the cwd rail starts in the left half of the row defer the same way.

## Steering-inbox doorbell

The steering channel's one behavioral assumption - a real worker agent follows the constant self-describing doorbell line (list the inbox, read and act on its records in numeric order, then `mv` each into `handled/`) - was verified on 2026-08-23 against every installed verified harness, on tmux 3.6a, macOS arm64, on an isolated private socket, driving the REAL `bin/fm-send.sh` end to end (durable record plus doorbell, with one mid-wait re-ring playing the watcher's role).

```sh
FM_SEND_INBOX_LIVE_E2E=1 tests/fm-send-inbox-doorbell-live-e2e.test.sh
```

Observed output (combined across the full run and the grok rerun after the advisory-skip narrowing landed):

```text
ok - claude (2.1.241 (Claude Code)): the doorbell reached a real worker, which acted and acked with the mv
ok - codex (codex-cli 0.147.0): the doorbell reached a real worker, which acted and acked with the mv
ok - opencode (1.18.21): the doorbell reached a real worker, which acted and acked with the mv
ok - pi (0.84.1): the doorbell reached a real worker, which acted and acked with the mv
# grok (grok 1.0.5 (5115b46bc909) [stable]): idle composer never classified empty; proceeding as production does (advisory check skips only on pending)
ok - grok (grok 1.0.5 (5115b46bc909) [stable]): the doorbell reached a real worker, which acted and acked with the mv
# harness absent, not verified here: kimi
ok - muse (Muse Code 0.2.1 (0.2.1-R1215.1)): the doorbell reached a real worker, which acted and acked with the mv
```

All six installed harnesses honored the doorbell contract with real model turns: each listed the inbox named by the doorbell, read its record, executed the instruction inside it, and acknowledged with the atomic `mv`.
Two findings from the run shaped the shipped behavior: an OpenCode vendor update modal swallowed the first doorbell and the single re-ring recovered it, which is exactly the watcher ladder's job; and grok 1.0.5's idle composer never classified `empty` in that run, which motivated the ring's advisory pre-check not to skip on ambiguity - a doorbell into an ambiguous composer is a recoverable constant line, while skipping on ambiguity would starve steering for any harness the classifier cannot positively identify.
The current pending-composer ring contract is owned by `bin/fm-task-inbox-lib.sh`.
Kimi was not installed on the verification machine; its receive path is the same one-line-plus-shell contract, and the portable ladder and enqueue regressions in `tests/fm-task-inbox.test.sh` and `tests/fm-send-inbox.test.sh` cover every harness-independent half.
This guard is the refresh command after any harness upgrade; it spends a small number of real tokens per installed harness, reports an absent harness explicitly, and refuses a run that verified nothing.

The doorbell no longer prints the inbox's absolute path, so its length no longer grows with the home's depth.
It names the inbox as `"$FM_TASK_INBOX"`, which `bin/fm-spawn.sh` exports into every launch as the absolute `state/<task>.inbox` path, followed by the short `<task>.inbox` name; the brief's full path remains the fallback for a worker launched without that export.
The guard now launches each worker with `FM_TASK_INBOX` exported and no brief, so the worker must resolve the inbox from the doorbell and its environment alone.
It is the refresh command for that shape, which has not yet been recorded live here.
The run below, on 2026-09-30 on tmux 3.6, Linux (WSL2), with the same command, covered the earlier brief-primed shape, whose doorbell named only the short `<task>.inbox` name and whose guard gave each worker the brief's steering-inbox sentence before the steer:

```text
ok - claude (2.1.285 (Claude Code)): the doorbell reached a real worker, which acted and acked with the mv
ok - codex (codex-cli 0.157.0): the doorbell reached a real worker, which acted and acked with the mv
ok - opencode (1.18.33): the doorbell reached a real worker, which acted and acked with the mv
# harness absent, not verified here: grok
# harness absent, not verified here: kimi
# harness absent, not verified here: muse
```

OpenCode needed `FM_SEND_INBOX_LIVE_TIMEOUT=560` because its configured model was still mid-turn at the default 240 seconds.

## Waiting-worker command ceilings

The `# Waiting` section of the ship and scout briefs (`bin/fm-brief.sh`) has a worker hold every external wait inside one blocking shell command, bounded by what its harness lets one command run.
That section is generated only when `config/wait-no-turns` is present.
Those bounds were read from the installed vendor code on 2026-09-11, macOS arm64, with codex-cli 0.154.0 and Claude Code 2.1.268.

```sh
strings -n 20 "$(readlink -f "$(command -v codex)")" | grep -o "Non-empty writes default to [^.]*; empty polls wait [^.]*\."
strings -n 8 "$(readlink -f "$(command -v claude)")" | grep -oE '=120000,[A-Za-z0-9_$]+=600000;' | head -1
```

Observed output:

```text
Non-empty writes default to 250 ms and cap at 30000 ms; empty polls wait 5000-300000 ms by default.
=120000,ARo=600000;
```

Codex yields a still-running command back to the model, and one empty `write_stdin` poll then waits up to 300000 ms.
Claude Code's Bash tool defaults to 120000 ms and accepts at most 600000 ms; `BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS` override those two values.

Claude Code also constrains the shape of a wait, not only its length, so the brief has to name the shape that is allowed rather than only forbid the ones that are not.
Run as separate Bash tool calls on 2026-09-14 with Claude Code 2.1.268:

```sh
until [ -e /tmp/fm-wait-probe ]; do sleep 30; done   # ran to completion, rc=0
sleep 61; echo "rc=$?"                               # rc=0
sleep 40; echo "checked at $(date +%s)"              # rc=0
```

An earlier `sleep 60` chained ahead of a status check was refused before execution, with a message pointing at `Monitor` with an until-loop and at `run_in_background: true`, and adding "Do not chain shorter sleeps to work around this block".
The blocking foreground `until` loop is therefore the wait a Claude Code worker may use, and it is what the brief names, because the refusal's own `run_in_background` suggestion is the one shape a waiting worker must not take: a backgrounded call returns at once and so does not wait at all.
The brief's portable regression is `tests/fm-brief.test.sh`; rerun these commands after upgrading either harness and update the numbers in the brief when they move.

## Gemini

The Gemini crewmate adapter was verified on 2026-09-04 with gemini-cli 0.58.0 on Linux, Node v24.20.0, tmux 3.4.
Every check below ran in throwaway scratch worktrees against the real CLI; no task worktree was used and no agent was left running.
The credential was supplied only through the `GEMINI_API_KEY` environment variable and its value appears nowhere in this record.

### Trust options are not equivalent

The refusal an untrusted launch produces, and its headless exit status:

```sh
gemini -p 'say OK'; echo "rc=$?"
```

```text
Gemini CLI is not running in a trusted directory. To proceed, either use `--skip-trust`, set the `GEMINI_CLI_TRUST_WORKSPACE=true` environment variable, or trust this directory in interactive mode.
rc=55
```

Both documented options clear that refusal, but only one loads project configuration.
The A/B below ran twice in ONE worktree carrying a project `AfterAgent` hook, with the same config home and the same prompt, changing only the trust mechanism:

```text
--skip-trust                 project-hook-fired=NO   untrusted-warnings=0   turn=✦ ECHO
TRUST_WORKSPACE=true         project-hook-fired=YES  untrusted-warnings=0   turn=✦ FOXTROT
```

`gemini skills list` names the cause directly in the untrusted case:

```text
Skipping project agents due to untrusted folder. To enable, ensure that the project root is trusted.
Project hooks disabled because the folder is not trusted.
```

This is why `bin/fm-spawn.sh` launches with `GEMINI_CLI_TRUST_WORKSPACE=true` and why `--skip-trust` must not be substituted for it.

### Busy signal

A full turn was captured every two seconds. The status row above the separator carries the one ASCII token, and the phase text beside it is model-generated:

```text
busy_1 | 1 |  ⠸ Thinking... (esc to cancel, 1s)
busy_5 | 1 |  ⠸ Begin Counting Methodically (esc to cancel, 9s)
busy_6 | 1 |  ⠇ Continue Enumerating Concepts (esc to cancel, 11s)
busy_7 | 0 |
busy_12 | 0 |
```

The idle capture taken before the prompt also contained no `(esc to cancel,`.
Because the phase text varies per turn and the spinner is braille, neither is usable; `(esc to cancel,` is the only stable rendered token, and the adapter uses the semantic hooks below as its actual state source.

### Hook lifecycle

`BeforeAgent`, `AfterAgent`, `SessionStart`, and `SessionEnd` were registered on one probe that appends its event name, then driven through a normal turn, an Escape interrupt, and `/quit`:

```text
--- after startup ---   SessionStart
--- mid-turn ---        SessionStart, BeforeAgent
--- after INTERRUPT --- SessionStart, BeforeAgent, AfterAgent
--- after /quit ---     SessionStart, BeforeAgent, AfterAgent, SessionEnd, SessionEnd
```

Two facts the adapter depends on come from that run: `AfterAgent` closes a turn that was CANCELLED, not only one that completed, and `SessionEnd` fired TWICE for a single `/quit`, so the repeated idle event must be harmless.
The `AfterAgent` payload carried the worktree as `cwd`, which is what binds a hook to its task:

```text
keys: ['cwd', 'hook_event_name', 'prompt', 'prompt_response', 'session_id', 'stop_hook_active', 'timestamp', 'transcript_path']
hook_event_name = AfterAgent
stop_hook_active = False
prompt = 'Say the single word CEDAR and stop.'
```

On the cancelled turn the same payload carried `prompt_response = '[no response text]'`.

### Autonomous end-to-end worker

One throwaway worker was launched exactly as the spawn launches one - positional brief, `-y`, workspace trust - and observed from start to idle:

```text
t=5s   (esc to cancel, 2s)
t=30s  busy marker present
idle at ~34s, busy marker count 0
worker-output.txt: DELIVERED
turn-end hook fires: 1
```

Its pane showed `✓ WriteFile worker-output.txt → Accepted (+1, -0)` with no approval gate, confirming `-y` runs unattended, and `Executing Hook: fm-turn-end` in the status row after the turn.

The adapter was then driven through the REAL `bin/fm-spawn.sh` and `bin/fm-control.sh` against a real Gemini pane in an isolated home:

```text
spawned gm-e2e harness=gemini kind=ship mode=no-mistakes yolo=off window=... worktree=...
hooks installed by spawn (state/<id>.gemini-settings.json): ['BeforeAgent', 'AfterAgent', 'SessionEnd']
t=4s   state: working · source: pane · harness busy (gemini-hook)
t=8s   state: working · source: pane · harness busy (gemini-hook)
after turn: v1 gen=... state=idle source=gemini-hook event=after-agent
e2e-output.txt: SEAWORTHY
interrupt-delivered gm-e2e harness=gemini backend=tmux verified=agent-alive cancel=unconfirmed
after interrupt: v1 gen=... state=idle source=gemini-hook event=after-agent
stopped gm-e2e harness=gemini backend=tmux endpoint=... worktree=...
```

The interrupt line is the one worth keeping: `AfterAgent` closed the record on a CANCELLED turn, which is why a gemini interrupt needs no `fm-interrupt` fallback event.
A single Escape on a long turn printed `ℹ Request cancelled.`, dropped the busy token, and left the agent running; `/quit` then exited with status 0 and printed `To resume this session: gemini --resume <session-id>`, and resuming by that id restored the full transcript.

### Identity markers

Env var NAMES were read from a real Gemini tool process launched under a Claude primary; no value of `GEMINI_API_KEY` was read.

```text
GEMINI_CLI=[1]
AI_AGENT=[claude-code_2-1-260_agent]
TRUSTWS=[true]
CLAUDECODE=[1]
```

`GEMINI_CLI` is unset in the launching environment, so it is Gemini's own; `CLAUDECODE` is inherited, which is why `bin/fm-harness.sh` tests `GEMINI_CLI` first.
`AI_AGENT` carried the CLAUDE primary's value and is therefore an inherited launcher marker, never a Gemini identity.

Ancestry cannot substitute for the marker on this platform:

```sh
node -e 'const{execSync}=require("child_process");console.log(execSync("ps -o comm= -p "+process.pid).toString().trim())'
```

```text
MainThread
```

The shipped CLI is a node bundle, so its live process never presents as `node` and neither ancestry arm matches it.

The same shape breaks pane liveness, which the end-to-end run surfaced as a hard refusal rather than a silent wrong answer:

```text
error: task gm-e2e's endpoint reads 'ambiguous' rather than a positively classified state; refusing to send a lifecycle key into an unattributed endpoint
```

A live gemini pane's foreground group read `comm=MainThread` and `argv0=/home/<user>/.local/node/bin/node`, so `bin/fm-gemini-lib.sh` now identifies it from argv[1] instead.
After that change the same endpoint classified `alive` while the worker ran and `dead` once it exited, so the rule is not simply always positive.
`tests/fm-gemini-harness.test.sh` pins that boundary so it is not later documented away, and `tests/fm-busy-adapter-wiring.test.sh` drives the generated hooks through the real writer and classifier.

```sh
bin/fm-test-run.sh tests/fm-gemini-harness.test.sh tests/fm-busy-adapter-wiring.test.sh
```

### Credential wedge and its blast radius

With no resolvable credential the pane wedges on `Enter Gemini API Key` rather than failing.
That dialog is a credential FIELD, so lifecycle text sent to a wedged pane is submitted into it and stored.
Observed after an ordinary exit was delivered to such a pane: a `~/.gemini/gemini-credentials.json` (mode 0600) appeared that had not existed before, and a later credential-less run stopped refusing cleanly and instead reached the API:

```text
before: rc=41  When using Gemini API, you must specify the GEMINI_API_KEY environment variable.
after : rc=1   API key not valid. Please pass a valid API key.  (API_KEY_INVALID)
```

Clearing that stored credential restored both behaviours:

```text
GEMINI_API_KEY=<from the operator's own store> gemini --skip-trust -p 'Reply with exactly the word NOVEMBER.'  ->  NOVEMBER  rc=0
env -u GEMINI_API_KEY gemini --skip-trust -p hi                                                              ->  rc=41
```

The adapter reference records the operational rule this produces: never drive lifecycle text into a gemini pane showing that dialog; treat it as a credential blocker and retire the endpoint instead.
The credential must also be present before the session-provider daemon starts, since a long-lived tmux or Herdr server hands panes the environment it was started with.

### Settings placement

Firstmate's hooks are NOT written into the worktree's `.gemini/settings.json`, because unlike Claude's `settings.local.json` that path is the project's own committed settings file.
They go to a firstmate-owned `state/<id>.gemini-settings.json` reached through `GEMINI_CLI_SYSTEM_SETTINGS_PATH`.
Two measurements support that choice.
Hooks from the system layer fired under `--skip-trust` in an untrusted folder, so the busy contract does not depend on the trust decision:

```text
=== events (UNTRUSTED workspace, --skip-trust) ===
BeforeAgent
AfterAgent
```

And hook arrays MERGE across layers rather than overriding, so a project's own hooks keep running alongside firstmate's:

```text
=== which AfterAgent hooks ran (trusted workspace, both layers define AfterAgent) ===
PROJECT
SYSTEM
```

A second end-to-end spawn against a project that already committed its own `.gemini/settings.json` confirmed the file was untouched, that `git status` reported only the worker's own new output file, and that teardown removed firstmate's settings file:

```text
t=4s   state: working · source: pane · harness busy (gemini-hook)
t=8s   state: working · source: pane · harness busy (gemini-hook)
after turn: state=idle source=gemini-hook event=after-agent
e2e2-output.txt: ANCHOR
project .gemini/settings.json: {"context":{"fileName":"GEMINI.md"}}   (unchanged)
interrupt-delivered gm2 harness=gemini backend=tmux verified=agent-alive cancel=unconfirmed
stopped gm2 harness=gemini backend=tmux
teardown gm2 complete; state/gm2.gemini-settings.json removed
```

### Not verified

Gemini as a PRIMARY or SECONDMATE runtime is unverified and is refused by `bin/fm-spawn.sh`: no wake protocol exists under `docs/supervision-protocols/` and no turn-end guard adapter was built or exercised.
No reasoning-effort axis was found; `gemini --help` on 0.58.0 exposes no effort, reasoning, or thinking flag, so the record-and-omit contract applies.

## Herdr

The compatibility floor is protocol 14.
The whole real-Herdr lane's latest active verification uses both Herdr 0.7.4 protocol 16 and Herdr 0.8.0 protocol 19 on macOS aarch64, while focused Herdr 0.7.5 protocol 17, earlier protocol-16, protocol-14, and 0.7.3 evidence is retained where it defines current behavior or fallbacks.
Protocol 17 keeps every protocol-16 feature gate satisfied; the event and workspace-move floors remain 16.
Default-on presentation projection has its own floor at Herdr 0.8.0, protocol 19, verified below.

Projected worktree entry was verified on 2026-11-03 with Herdr 0.9.5 on macOS arm64:

```sh
bash bin/fm-test-run.sh tests/fm-herdr-projected-cd-live-e2e.test.sh
```

```text
ok - Herdr 0.9.5 projected spawn enters its recorded copy (delayed=0)
ok - Herdr 0.9.5 projected spawn enters its recorded copy (delayed=1)
```

This token-free guard provisions only a named non-default Herdr lab session, drives the real projected spawn, cd, and cwd assertion, and verifies the exact foreground cwd against the recorded copy.
On a supported Herdr below the presentation floor, where `fm_backend_herdr_presentation_release_supported` keeps spawns flat, it prints a skip naming the release and exits 0 instead of running the projected cases.
Its delayed case holds the first real cd behind a 15-second shell command and verifies exactly one resend; its ordinary case verifies no redundant cd.
The lease fixture returns a disposable clone without accessing a shared Treehouse pool.
The portable delayed, dropped, and never-moving entry regressions are in `tests/fm-spawn-herdr-lease.test.sh`.

Core read-only probes:

```sh
herdr --version
herdr status --json | jq -c '{client:.client.protocol,server:.server.protocol}'
herdr api schema --json | jq -c '.schemas.subscription_event["$defs"].SubscriptionEventKind.enum'
```

Observed protocol-16 compatibility shapes:

```text
herdr 0.7.5
{"client":17,"server":17}
["pane.output_matched","pane.agent_status_changed","pane.scroll_changed"]
```

The CLI matrix was checked directly:

| Guarantee | Command shape | Result |
| --- | --- | --- |
| Explicit session routing | `herdr <verb> ... --session <name>` | Reached the named session even while another server was running. |
| Literal send | `herdr pane send-text <pane> <text> --session <name>` | Left text unsubmitted until Enter. |
| Keys | `herdr pane send-keys <pane> enter|escape|ctrl+c --session <name>` | Enter and Escape worked; Ctrl-C interrupted foreground work. |
| Capture | `herdr pane read <pane> --source recent --lines N` | Small N could return empty below viewport height; a 200-line request plus local trim was stable. |
| Viewport capture | `herdr pane read <pane> --source visible` | Verified on 2026-09-17 against Herdr 0.8.0 (protocol 19): `herdr pane read --help` documents `--source <SOURCE>` with `[possible values: visible, recent, recent-unwrapped, detection]`; `--source visible` exited 0 and returned 51 lines (the viewport) while `--source recent --lines 200` returned 200. This is the viewport-only read behind `fm_backend_herdr_visible_capture`, which Kimi's trust-dialog gate requires. |
| Styled viewport capture | `herdr pane read <pane> --source visible --format ansi` | Verified on 2026-09-26 against Herdr 0.9.0 with Claude Code 2.1.283: the flag pair exited 0 and returned the viewport with SGR attributes intact, which is the styled read behind `fm_backend_herdr_visible_capture_ansi` that ghost/placeholder stripping needs (see "Claude exit behind the slash-command popup" below). |
| Native state | `herdr agent get <pane>` | Working and done transitions were visible on some harnesses; live Claude Code 2.1.236 on Herdr 0.8.0 kept `agent_status=idle` for an entire landed turn, including a multi-second tool call, so submit confirmation falls through to the shared composer verdict. Native `busy` remains positive activity evidence, while native `idle` cannot close a turn and the adapter's semantic lifecycle decides worker state. |
| Restart | guarded named-session stop then start | Workspace, tab, pane, and labels persisted; the agent process and registration did not. |
| Close | `herdr pane close <pane> --session <name>` | The exact one-pane task tab closed; closing a final tab could remove the workspace. |

All destructive verification used `bin/fm-herdr-lab.sh` with a non-default `fm-lab-` name and a byte-identical default-session tripwire.
No ambient `herdr server stop` command is a supported test operation.

### fm-remote server birth and login-keychain access

Measured 2026-09-09 on macOS 26 (Darwin 25.6.0) aarch64 with Claude Code 2.1.266 and Herdr 0.9.0, the guarantee behind `bin/fm-remote-herdr-guard.sh` and the doctor's `herdr-server` check: login-keychain access follows the audit session a process was born into, never the launch shape or the shell.

Same user, same `HOME`, same login keychain item, three births, probed with `launchctl managername`, `getaudit_addr` (a compiled probe), `security find-generic-password -a "$USER" -w -s "Claude Code-credentials"` (output withheld), and `claude auth status`:

| Birth | `managername` | audit session | `security ... -w` | `claude auth status` |
| --- | --- | --- | --- | --- |
| `gui/501` LaunchAgent, bare `ProgramArguments`, `launchctl bootstrap` + `kickstart -k` mid-session | Aqua | asid 100038 (the `gui/501` asid), `HAS_GRAPHIC_ACCESS HAS_TTY HAS_CONSOLE_ACCESS HAS_AUTHENTICATED` | exit 0 | `loggedIn: true` |
| `gui/501` LaunchAgent, `zsh -l -c 'exec ...'`, same reload | Aqua | asid 100038, same flags | exit 0 | `loggedIn: true` |
| `user/501` LaunchAgent (`LimitLoadToSessionType=Background`), same reload | Background | asid 100056, flags `0x0` | exit 36 `User interaction is not allowed.`, item metadata still readable | `loggedIn: false`, `authMethod: none` |

Claude Code 2.1.266 maps that exit 36 (and 44) to "no keychain data" and reads `~/.claude/.credentials.json` instead; with a stale file it prints `Failed to authenticate: OAuth session expired and could not be refreshed` (interactive: `Login expired · Please run /login`).

Candidate birth markers were read with `ps -Eww -o command= -p <pid>` for own-uid processes, noting that macOS hides the environment of Apple platform binaries such as `/bin/sleep` and that a herdr server is never one.

```text
launchd-born herdr server (child of launchd, gui/501):  XPC_SERVICE_NAME=org.nix-community.home.herdr-server  no SSH_*
SSH-born herdr server (child of `herdr --session fm-remote remote-client-bridge` under `sshd-session: user@notty`):  SSH_CLIENT=... SSH_CONNECTION=...  no XPC_SERVICE_NAME
```

`XPC_SERVICE_NAME` identifies a launchd label but does not identify its domain, because the Background `user/501` job also carried that variable while lacking keychain access.
The owner classifier therefore accepts that label only when `launchctl print gui/<uid>/<label>` identifies the owner pid or the label is loaded in `gui/<uid>` but not `user/<uid>`.
`XPC_SERVICE_NAME=0`, including a value inherited by a herdr live-handoff child, remains unknown.
`FM_REMOTE_JOB_ACTIVE=1` proves the Aqua worker only when `dev.firstmate.remote-job` is loaded in `gui/<uid>` but not `user/<uid>`.

The SSH-born row was read on the remote host whose `dev.firstmate.herdr.fm-remote` job showed `state = spawn scheduled`, `runs = 239`, `last exit code = 1` and a log repeating `error: herdr server is already running`: herdr's remote attach had started the session's server as its own child before the login session existed, and launchd's copy lost the socket on every retry.
`pgrep -f` did not list the herdr server's argv on macOS; `lsof -U -a -c herdr -F pn` named the socket owner.

A separate foreground-supervision check ran on 2026-09-09 on macOS 26 (Darwin 25.6.0) with Herdr 0.9.0 using the throwaway Aqua launch agent `dev.fm-rca.herdr-fg`.
Its `ProgramArguments` ran `/run/current-system/sw/bin/zsh -l -c "exec /etc/profiles/per-user/kunchen/bin/herdr server --session fm-lab-fg-90381-18985"`, with `KeepAlive={SuccessfulExit=false}` and `ThrottleInterval=10`, after `launchctl bootstrap gui/501 <plist>` and `launchctl kickstart -k gui/501/dev.fm-rca.herdr-fg`.
`launchctl print gui/501/dev.fm-rca.herdr-fg` reported `state = running` and `pid = 4806`.
`lsof -U -a -c herdr -F pn` named pid 4806 as the owner of `~/.config/herdr/sessions/fm-lab-fg-90381-18985/herdr.sock`.
`ps -o pid,ppid,command -p 4806` reported `4806 1 /etc/profiles/per-user/kunchen/bin/herdr server --session fm-lab-fg-90381-18985`, and its environment carried `XPC_SERVICE_NAME=dev.fm-rca.herdr-fg`.
No other herdr process existed for that session, and after 15 seconds the job remained running with pid 4806.
After a guarded `herdr session stop`, the job reported `state = not running` and `last exit code = 0`, and it stayed at rest through the throttle interval.
A second `launchctl kickstart -k gui/501/dev.fm-rca.herdr-fg` started pid 45574, which was also the new socket owner.
This proves that `herdr server` remains in the foreground as the launchd job, so the guard's final `exec` supplies the intended supervision and the earlier server that survived `launchctl bootout` was the unrelated SSH-bridge-born process.

`bin/fm-test-run.sh tests/fm-remote-herdr-guard.test.sh` pins the resulting decision table against real marker-carrying processes, and `tests/fm-remote-doctor.test.sh` pins the doctor's verdicts on the same markers.

### Client selection

Measured 2026-09-08 on a macOS aarch64 host running a Herdr 0.9.0 server (protocol 22) for the `fm-remote` session while `~/.local/bin/herdr` still held the self-updated 0.8.2 client (protocol 20) ahead of the Nix-managed 0.9.0 client on the remote-job `PATH`.

```sh
~/.local/bin/herdr --version
~/.local/bin/herdr pane get wCY:p2 --session fm-remote; echo "rc=$?"
~/.local/bin/herdr status --json --session fm-remote | jq -c '{c:.client.protocol,s:{running:.server.running,protocol:.server.protocol,compatible:.server.compatible}}'
herdr status --json --session fm-remote | jq -c '{c:.client.protocol,s:{running:.server.running,protocol:.server.protocol,compatible:.server.compatible}}'
```

```text
herdr 0.8.2
{"id":"cli:pane:get","error":{"code":"protocol_mismatch","message":"client protocol 20 is older than server protocol 22; upgrade the Herdr client before using this command"}}
rc=1
{"c":20,"s":{"running":true,"protocol":22,"compatible":false}}
{"c":22,"s":{"running":true,"protocol":22,"compatible":true}}
```

The refusal is a JSON error on stderr with exit 1 and empty stdout, and both client generations report `.server.compatible` and `.server.protocol` per named session, which is what the selection in `bin/backends/herdr.sh` reads.
`tests/fm-backend-herdr.test.sh` pins the bypass, same-process same-session caching, cross-session isolation, forced reselection, and both status shapes against fakes; `tests/fm-backend-herdr-smoke.test.sh` refreshes the real status normalization against the installed binary's running lab server.

### Session directory

Measured 2026-10-15 on Linux x86_64 with Herdr 0.9.5, reading only `status`: the default and an empty `sessions/probe` session under a fresh `XDG_CONFIG_HOME` with no server, then the host's running `firstmate` session.

```sh
herdr --version
d=$(mktemp -d /tmp/hx.XXXXXX); mkdir -p "$d/herdr/sessions/probe"
for s in default probe; do XDG_CONFIG_HOME="$d" herdr --session "$s" status --json | jq -c --arg d "$d" '{session: .server.session, running: .server.running, socket: (.server.socket | sub("^" + $d; "$XDG_CONFIG_HOME"))}'; done
herdr --session firstmate status --json | jq -c --arg h "$HOME" '{session: .server.session, running: .server.running, socket: (.server.socket | sub("^" + $h; "~"))}'
HERDR_SOCKET_PATH=/tmp/xx/zz.sock herdr --session default status --json | jq -c '.server.socket | sub("^" + env.HOME; "~")'
```

```text
herdr 0.9.5
{"session":null,"running":false,"socket":"$XDG_CONFIG_HOME/herdr/herdr.sock"}
{"session":"probe","running":false,"socket":"$XDG_CONFIG_HOME/herdr/sessions/probe/herdr.sock"}
{"session":"firstmate","running":true,"socket":"~/.config/herdr/sessions/firstmate/herdr.sock"}
"~/.config/herdr/herdr.sock"
```

A session whose server is stopped still reports its socket, the socket's directory is the session directory `herdr session list --json` reports as `session_dir`, it follows `XDG_CONFIG_HOME`, and an inherited `HERDR_SOCKET_PATH` does not move it under `--session`, so the [externally managed server](../herdr-backend.md#externally-managed-servers) markers stay readable through a restart without an extra Herdr call.
The `status` read created nothing under the fresh config directory.
`tests/fm-backend-herdr.test.sh` pins the marker behavior against fakes.

### Submit confirmation

Measured 2026-08-19 against Herdr 0.8.0 and Claude Code 2.1.236 in an isolated `fm-lab-` session.

`herdr agent get` reported `agent_status=idle` on every sample across a landed one-word turn and an 8-second `sleep` tool call, while the pane rendered `Pontificating…` then `Sock-hopping… (11s · ↓ 234 tokens)`.
`fm_backend_herdr_send_text_submit` therefore cannot treat native idle as proof of a swallow.
The portable regressions in `tests/fm-backend-herdr.test.sh` and `tests/fm-composer-lib.test.sh` pin the verdicts: native idle plus a cleared composer is delivery, proven pending plus idle is a swallow, and proven pending plus a generating busy signal is a queued Enter.
Refresh the live Claude proof with:

```sh
FM_HERDR_SUBMIT_CONFIRM_LIVE=1 tests/fm-herdr-submit-confirm-live-e2e.test.sh
```

Observed 2026-08-19:

```text
ok - live Herdr submit confirm: Claude Code (2.1.236 (Claude Code)) on herdr 0.8.0 reports empty for a landed idle steer
```

### Claude exit behind the slash-command popup

Measured 2026-09-26 against Herdr 0.9.0 and Claude Code 2.1.283 in an isolated `fm-lab-` session.

Typing `/exit` makes Claude Code render its command popup between the composer and the pane bottom: about 19 menu rows below a solid rule pair, with the footer row last.
The composer row lands outside a bounded 20-row tail of the pane, so the adapter's bounded composer reads reported the composer as empty while it actually held `/exit`.
The pre-Enter payload proof then judged the typed command unsent, pressed Ctrl+U, and reported `send-failed` without ever pressing Enter, so `bin/fm-control.sh exit` never exited the worker (and `bin/fm-secondmate-restart.sh` inherited the failure through its exit step).

The fix captures the FULL VISIBLE VIEWPORT for every herdr adapter composer read (`pane read --source visible [--format ansi]`, `fm_backend_herdr_composer_state` and `fm_backend_herdr_composer_content`): the composer is by definition inside the viewport, and the viewport is the one bound that always contains it.
The shared inbox pending-line confirmation read (`bin/fm-task-inbox-lib.sh`) stays a bounded tail on every backend, herdr included; its payloads are task lines, not slash commands, so the popup shape does not arise there.
The popup rows sit below the composer's closing rule, which is a structural edge row, so the shared classifier still selects only the composer and the unmarked menu rows never read as typed text (Claude Code 2.1.283 through 2.1.289; 2.1.291 marks the selected row, see below).
Verified live in the lab: with the popup up the state read answers `pending` (previously `empty`) and the payload proof returns `/exit` (previously empty), the submit presses Enter, and the Claude process exits, leaving the shell prompt.
Growing the window only adds rows above the composer, so the bottom-most-shape selection, the footer zone, and every previously passing verdict are unchanged.

Portable regressions (they fail against the bounded-tail reads and pass against the viewport reads):

```sh
tests/fm-backend-herdr.test.sh
```

```text
ok - fm_backend_herdr_composer_state: a slash-command popup cannot hide a typed composer
ok - fm_backend_herdr_send_text_submit: a typed slash command hidden behind its popup is still proven and submitted
```

Live guard (the `/exit` scenario of the opt-in guard, verifying the agent actually exited):

```sh
FM_HERDR_SUBMIT_CONFIRM_LIVE=1 tests/fm-herdr-submit-confirm-live-e2e.test.sh
```

```text
ok - live Herdr submit confirm: Claude Code (2.1.283 (Claude Code)) on herdr 0.9.0 proves and submits a typed /exit behind its command popup
```

#### Claude Code 2.1.291 marks the popup's selected row

Measured 2026-10-06 against Herdr 0.8.2 and Claude Code 2.1.289 and 2.1.291 on Haiku 4.5 in isolated `fm-lab-` sessions.

Claude Code 2.1.283, 2.1.284, 2.1.285, 2.1.286, 2.1.288 and 2.1.289 draw the popup's selected row unmarked.
Claude Code 2.1.291 (2.1.290 is not installed here) draws it as `  ❯ /exit    Exit the CLI`, with the `❯` its composer uses, and indents the other rows to match.
That row lies below the composer's closing rule, so it became the bottom-most bare agent-glyph row.
The footer-zone rule deliberately keeps a row that leads with the envelope's own glyph as a live composer, so the popup's first row won the selection and the typed command's read-back was the whole popup list.
The pre-Enter payload proof then judged `/exit` unsent, pressed Ctrl+U, and reported `send-failed`, so `bin/fm-control.sh exit` and every slash command sent through `bin/fm-send.sh` failed on Herdr.
The notification row Claude draws under the composer when it runs inside another Claude session is not involved: the failure reproduces without it.

`_fm_composer_select_cursorless` now demotes that row to the envelope above it, through `_fm_composer_bare_is_popup_selection`, only when every condition holds.
The row lies below the closing row of a glyph-proven envelope.
That envelope's own glyph row leads with the agent glyph, with no side border to strip (a bordered box keeps its previous reading), and holds typed text opening with `/`, read under the ghost-strip threshold of the calling read (the state read or the payload read), so the read it falls back to is never empty: typed text that read strips as ghost cannot license the demotion.
The row opens with `/` (or `…`, a name truncated to its column) and carries a gap of two or more spaces before its description, which a numbered-choice dialog row lacks.
The selected popup row is not always the typed text (typing `/` selects the first command, and a long plugin command name is truncated), so no equality check is made.
Any other row keeps its previous reading, and none of these can read `empty`.
Unverified follow-up: a bordered-box composer with the marked popup row below it is out of scope here.
Its state read still refuses with `pending`, but its payload read still returns the popup list, so a slash command typed into a boxed Claude 2.1.291 composer would still fail the pre-Enter proof; no capture or live run here shows 2.1.291 drawing the box with the popup up.
The other cursorless backend (orca) shares this classifier and inherits the change without a live check here.

Portable tests run against real captures (`tests/captures/claude-2.1.291-slash-popup`):

```sh
tests/fm-composer-lib.test.sh
tests/fm-backend-herdr.test.sh
```

These three are before-and-after regressions: each fails against the previous classifier and passes against this one.

```text
ok - fm_composer_extract_selected_content: Claude 2.1.291's marked popup row is not read as the composer
ok - fm_backend_herdr_composer_content: Claude 2.1.291's marked popup row is not read as the typed command
ok - fm_backend_herdr_send_text_submit: a slash command behind Claude 2.1.291's marked popup row is proven and submitted
```

These two are guards, not regressions: they already pass against the previous classifier, and check that the demotion keeps the refusals that classifier made.

```text
ok - fm_composer_classify_screen: the popup demotion needs typed slash text and the popup row shape, and never reads empty
ok - fm_backend_herdr_send_text_submit: with Claude 2.1.291's popup on screen a suffix, a placeholder plus remainder, or a prefix is still refused and cleared
```

Live guard, which fails against the previous classifier on 2.1.291 at the `/context` scenario (`send-failed`), with `ANTHROPIC_MODEL=claude-haiku-4-5-20251001` selecting the model (the pane banner reads `Haiku 4.5`):

```sh
FM_HERDR_SUBMIT_CONFIRM_LIVE=1 tests/fm-herdr-submit-confirm-live-e2e.test.sh
```

```text
ok - live Herdr submit confirm: Claude Code (2.1.291 (Claude Code)) on herdr 0.8.2 reports empty and renders the requested reply in isolated session fm-lab-herdr-submit-con-1098793-23839
ok - live Herdr submit confirm: Claude Code (2.1.291 (Claude Code)) on herdr 0.8.2 submits a U+2063 away-supervisor payload whose read-back drops the mark
ok - live Herdr submit confirm: Claude Code (2.1.291 (Claude Code)) on herdr 0.8.2 proves and submits a typed /context behind its command popup and renders its report
ok - live Herdr submit confirm: Claude Code (2.1.291 (Claude Code)) on herdr 0.8.2 proves and submits a typed /exit behind its command popup
```

The real control and steer paths, run by hand against Claude Code 2.1.291 in the lab with a scratch home whose task record names the pane, answered as follows.
`bin/fm-control.sh <id> exit` answered `error: the exit command could not be sent to task <id> on herdr` before the change and `stopped <id> harness=claude backend=herdr ...` after it.
`bin/fm-send.sh <id> /context` answered `error: text not sent to <endpoint> (herdr send failed; ...)` with exit 1 before the change, and exit 0 after it with Claude's `/context` output rendered.

### Claude background-task exit picker

Measured 2026-10-05 against Claude Code 2.1.289 in an isolated tmux session.
The Herdr lab was not running, so the Herdr path is covered by the existing fakes.
Typing `/exit` while a background shell is still running opens a picker whose selected row is "Exit and stop tasks" and whose footer is "Enter to confirm · Esc to cancel".
That screen still classifies as pending, the same verdict as unsubmitted composer text.
A second Enter would confirm the selected row.
The picker is recognised by its recorded structure only: the heading on its own line, then the selected row alone on its row, with `Enter to confirm · Esc to cancel` as the last non-blank row.
The same strings quoted above a normal composer, as a diff, this note, or a test fixture shows them, are not a picker.
Submit retries now stop after the Enter that opened the picker and report unknown.
A typed submit to a pane that already shows the picker types nothing and sends no Enter.
Exit reports that the worker is blocked on the Claude background-task exit picker and does not type another Enter.
A submit can return before any read sees the picker, so exit reads the screen once more when its wait for the agent to stop times out, and names the picker there too.
Exit does not report a stopped agent whose pane still shows the picker text as blocked on a prompt.
The watcher reads the picker with the same matcher on the stale-path capture it already takes for a worker.
A worker pane parked on it keeps the ordinary stale triage and schedule, and its plain stale reason and its final wedge escalation reason name the picker after `blocked-on-prompt:`; the deferral, dead-record, and declared-wait recheck reasons do not.
A second mate stays off that path, and a finished worker in away mode is handled as before.
That watcher and away-daemon reporting is covered by fakes in `tests/fm-watch-triage.test.sh` and `tests/fm-daemon.test.sh`, not by a live measurement.
No recorded screen was available for a model-downgrade confirmation, an MCP approval, or a Claude exit confirmation other than this picker, so those dialogs are not covered.
Refusing an Enter that would confirm a dialog restores an existing safety path, so it is not gated behind a flag.

### Prune and respawn

The real label-collision reproduction is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-prune-safety-e2e.test.sh
```

Observed guarantee: a pre-existing captain-owned workspace with a seed-shaped tab was adopted for routing but its tab was never eligible for prune because the current create call did not return that seed id.

Restart-husk replacement is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-respawn-idem-e2e.test.sh
```

Observed guarantee: a restored no-agent tab was replaced create-before-close, while a registered live agent caused refusal.

### Launcher workspace placement

Herdr exports its pane identity into every process it manages, checked on 2026-07-30 against Herdr 0.7.5 protocol 17 inside a guarded lab pane:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh
"$HERDR_LAB_HELPER" run "$LAB" pane run "$PANE" "sh -c 'env | grep ^HERDR | sort > /tmp/env.txt'"
```

```text
HERDR_ENV=1
HERDR_PANE_ID=w1:p1
HERDR_SESSION=fm-lab-fm-herdr-env-pro-65961-25535
HERDR_SOCKET_PATH=/Users/kunchen/.config/herdr/sessions/fm-lab-fm-herdr-env-pro-65961-25535/herdr.sock
HERDR_TAB_ID=w1:t1
HERDR_WORKSPACE_ID=w1
```

This complete injection shape is verified only for Herdr 0.7.5.
Firstmate requires both `HERDR_PANE_ID` and `HERDR_SOCKET_PATH` before accepting claimed launcher ancestry.

`pane get` reports the pane's current owning tab and workspace, which is what placement resolves from; the injected `HERDR_TAB_ID` and `HERDR_WORKSPACE_ID` are creation-time snapshots and are not read as current identity:

```sh
"$HERDR_LAB_HELPER" run "$LAB" pane get w1:p1 | jq -c '.result.pane | {pane_id,tab_id,workspace_id}'
```

```text
{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"}
```

Placement is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-launcher-workspace-e2e.test.sh
```

Observed guarantees on 2026-07-30 against Herdr 0.7.5 protocol 17:

```text
ok - real herdr E2E: with one 'firstmate' workspace and no herdr parent, a crewmate still lands in this home's own workspace without stealing focus
ok - real herdr E2E: the normal unique-label path is unchanged when the launcher's own pane identifies the workspace
ok - real herdr E2E: presentation spaces still create the isolated child workspace and bind it under the launcher's exact parent, without stealing focus
ok - real herdr E2E: with two 'firstmate' workspaces, a worker spawned from inside the second one lands in that exact workspace
ok - real herdr E2E: the duplicate-labeled sibling workspace is left entirely untouched and focus is preserved
ok - real herdr E2E: with a duplicated home label, a projected worker still hangs off the launcher's exact workspace and the sibling stays untouched
ok - real herdr E2E: an ambiguous home label with no launcher identity refuses before any worker endpoint exists
ok - real herdr E2E: a launcher pane that no longer exists refuses before any worker endpoint exists
ok - real herdr E2E: a secondmate launching its own worker gets the same exact-workspace guarantee, and its same-labeled sibling is untouched
ok - real herdr E2E: a --secondmate launch still stands up that secondmate's own workspace instead of inheriting the launcher's
ok - real herdr E2E: teardown closes only the worker's own pane and leaves the launcher, its workspace, and the same-labeled sibling intact
```

That suite's headline case runs `bin/fm-spawn.sh` inside a real Herdr pane, so the parent identity comes from Herdr's own injection rather than a composed environment.
Cross-session and contradictory bindings are covered deterministically in `tests/fm-backend-herdr.test.sh`, which can script a second server's socket without provisioning one.

### Per-home and presentation topology

Per-home behavior is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-workspace-per-home-e2e.test.sh
```

Observed guarantee: the primary and secondmate used distinct home workspaces, a child launched by the secondmate stayed in that secondmate workspace, list-live remained home-scoped, and exact cleanup did not affect sibling homes.

The complete projection suite ran on 2026-07-21 against Herdr 0.7.4 protocol 16:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-presentation-e2e.test.sh
```

Observed guarantees included:

```text
ok - real Herdr lab: primary and two secondmate homes each own a top-level contiguous child block
ok - real Herdr lab: concurrent primary/A/B spawns stay session-locked with zero focus drift
ok - real Herdr lab: session lock contention from a secondmate home falls back flat with no journal
ok - real Herdr lab: legacy projection labels and flat secondmate tabs are left unmigrated
ok - real Herdr lab: multi-home exact-pane teardowns restore captain focus without workspace close authority
ok - real Herdr lab validation completed on Herdr 0.7.4 with the default-session tripwire intact
```

The suite also covers lost or failed move responses, restart husks, missing and duplicate tokens, manual renames, concurrent cleanup, and exact focus restoration.

The mandatory projection suite ran again on 2026-07-24 against Herdr 0.7.5 protocol 16:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-presentation-e2e.test.sh
```

Observed restart-reclaim guarantees:

```text
ok - real Herdr lab: Hi Bit and Wheelhouse-style same-identity restarts reclaim one nested space with exact focus and idempotence
ok - real Herdr lab: secondmate restart binding and reclaim stay isolated to the exact child home and parent
ok - real Herdr lab: concurrent cross-home recoveries replace exact husks under one session lock with no focus drift
ok - real Herdr lab: missing, renamed, and duplicate tokens trigger zero destructive or adoptive calls, and live duplicate risk refuses launch
ok - real Herdr lab validation completed on Herdr 0.7.5 with the default-session tripwire intact
```

The projection suite ran again on 2026-08-04 against Herdr 0.8.0 protocol 19 for the default-on flip, where an absent `config/herdr-presentation-spaces` enables the projection and the value `off` opts out; since 2026-08-05 an absent file enables the projection only at or above the 0.8.0 floor recorded under "Presentation version floor" below, and `on` is the explicit opt-in that survives the floor:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-presentation-e2e.test.sh
```

Observed default and opt-out guarantees:

```text
ok - real Herdr lab: an opted-out spawn retains the Stage 1 Herdr command sequence with zero ordering calls
ok - real Herdr lab: a home that configured nothing is projected by default
ok - real Herdr lab: the primary presentation setting inherits into real secondmate homes
ok - real Herdr lab validation completed on Herdr 0.8.0 with the default-session tripwire intact
```

The projected spawn in that run used the historical empty opt-in file, so a home that had already enabled the projection keeps it without any migration step.
One concurrent cross-home recovery case refused under contention on a loaded machine and passed on an immediate rerun; recovery-path presentation lock contention remains a deliberate hard refusal by default rather than a flat fallback, which default-on makes reachable from any Herdr home.
Callers that need concurrent recoveries to serialize can pass `fm-spawn.sh --herdr-resume-lock-wait`.
The flag applies to a fresh ship or scout spawn, and the multi-task path forwards it to each per-pair spawn.
It has no effect on `--relaunch` and `--secondmate`, because those paths take no exact-resume presentation-order lock.
That run measured the default-on projection on Herdr 0.8.0 only, while the focus-flash regression below was last run on 0.7.5 before the flip, so neither run covered a defective release under default-on projection; the version floor and the focus-flash suite's Part C close that gap.

The restored-shell session-start cleanup ran on 2026-07-24 against Herdr 0.7.5 protocol 17:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-herdr-session-cleanup-e2e.test.sh
```

Observed guarantee: one exact home-local, journal-correlated, one-tab and one-pane childless idle shell was closed after restoration while the exact non-target focus and default fleet session remained unchanged, and a repeat run was a no-op.

### Workspace-removal focus safety

The focus-flash regression ran on 2026-08-05 against both Herdr 0.7.5 protocol 17 and Herdr 0.8.0 protocol 19 on macOS aarch64, with the 0.7.5 run using the pinned upstream release binary first on `PATH`:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-focus-flash-e2e.test.sh
```

Observed output on Herdr 0.7.5:

```text
ok - old path: the explicit last-pane close of a non-focused workspace stole focus (w3	w3:t1 -> w2	w2:t1)
ok - mitigation: every in-operation sample preserved exact focus while the doomed workspace was removed
ok - mitigation: no explicit close and no corrective focus were needed on the defective release
ok - fallback: a doomed pane holding a persistent child exhausts the proof and takes the plain explicit close
ok - fallback on a defective release: a bounded wrong-focus window of 4 samples was fully restored to the anchor
ok - version floor: herdr 0.7.5 protocol 17 remains conservatively below the floor with steal_live=1
ok - version floor: an unconfigured home falls back flat on herdr 0.7.5 and the explicit opt-in still projects
evidence: herdr=0.7.5 protocol=17 steal_live=1 floor_verdict=1 default-session-tripwire=armed
```

Observed output on Herdr 0.8.0:

```text
ok - old path note: this Herdr release preserves focus across the explicit close; continuing with outcome-only assertions
ok - mitigation: every in-operation sample preserved exact focus while the doomed workspace was removed
ok - fallback: a doomed pane holding a persistent child exhausts the proof and takes the plain explicit close
ok - fallback on a focus-preserving release: the plain explicit close preserved exact focus throughout
ok - version floor: herdr 0.8.0 protocol 19 is at or above the floor and preserves focus
ok - version floor: an unconfigured home stays projected on herdr 0.8.0 and the explicit opt-in agrees
evidence: herdr=0.8.0 protocol=19 steal_live=0 floor_verdict=0 default-session-tripwire=armed
```

The same guarded named-lab command passed on 2026-09-03 against Herdr 0.8.2 after this regression joined the required `real-herdr-gated` lane.
It reported `steal_live=0 floor_verdict=0 default-session-tripwire=armed`, with the fleet's default session unchanged before and after.

Part C is the case the suite could not reach before: a doomed pane whose shell holds a persistent background child fails the lone-idle-shell proof on every sample, so the plan takes the plain explicit close, in the geometry where the closing workspace's right neighbour is a spacer rather than the focused anchor.
On 0.7.5 that fallback exposed a bounded four-sample wrong-focus window and restored the anchor exactly; on 0.8.0 the same fallback exposed none, which is why default-on projection is floored at 0.8.0 rather than mitigated further below it.
The suite also cross-checks its own Part A measurement against the floor classifier on whatever release it runs, so a drifted protocol-to-release mapping fails there rather than silently gating on the wrong thing.

### Attached foreground viewer

A pseudo-terminal registers as a Herdr foreground client only when its window grid is non-zero.
`script` and a bare `pty.fork()` from a non-tty parent both start at 0x0, which is why PR #4131 could validate only the detached half of the teardown focus guard and left its four attached-client scenarios untested.
The guarded `viewer start` path fixes the pty at the proven 40-row by 120-column grid, sets that size on the master fd before the fork, and scrubs inherited `HERDR_*` variables, which makes the attached scenarios reachable from a headless runner.

Measured on 2026-09-11 against Herdr 0.9.0 protocol 22 on macOS 26.5.2 aarch64 with Python 3.14.6:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-herdr-attached-viewer-live-e2e.test.sh
```

```text
ok - attached viewer: a pty sized before the fork registers as a real Herdr foreground client
ok - attached viewer: a live client on the target tab refuses the close and keeps the pane
ok - attached viewer: focus moving onto the target between planning and mutation still blocks the close
ok - attached viewer: a close preserves the fresh non-target focus the viewer moved to
ok - attached viewer: the projection seeded-tab prune refuses while a live client watches it
ok - attached viewer: detaching releases the refusal, so the guard tracks the client and not the pointer
```

Both halves of the recipe are load-bearing, and each was measured by removing it from the helper and re-running the guard on the same host and release.
Dropping the `TIOCSWINSZ` call and dropping the environment scrub each left startup reporting `no_foreground_client`, followed by the guard failure:

```text
not ok - could not attach a real foreground Herdr viewer over a sized pty
```

Re-run this guard after every Herdr upgrade.
A release that changed the foreground-client contract, the window-grid requirement, or the nested-viewer refusal would fail here first, and the detached regressions would keep passing while saying nothing about it.

### Presentation version floor

Default-on presentation projection is floored at Herdr 0.8.0.
The floor's structural signal is the selected running server's protocol number, falling back to the client protocol only when that selected session positively reports no running server, and the release mapping was measured on 2026-08-05 by running each pinned upstream macOS aarch64 release asset's own `status --json` through the guarded lab helper:

| Release | Reported version | Protocol | Carries both upstream focus fixes | Floor verdict |
|---|---|---|---|---|
| v0.7.3 | 0.7.3 | 16 | no | below |
| v0.7.4 | 0.7.4 | 16 | no | below |
| v0.7.5 | 0.7.5 | 17 | no | below |
| preview-2026-07-21-0f10e1453a7f | 0.7.5-preview.2026-07-21-0f10e1453a7f | 17 | no | below |
| preview-2026-07-29-44b3adb12552 | 0.7.5-preview.2026-07-29-44b3adb12552 | 18 | yes | below |
| preview-2026-08-04-d78e3d3b5126 | 0.8.0-preview.2026-08-04-d78e3d3b5126 | 19 | yes | above |
| v0.8.0 | 0.8.0 | 19 | yes | above |

No build lacking both fixes reaches protocol 19, and every pre-fix build tops out at 17, so protocol 19 is a safe structural expression of the 0.8.0 floor.
The one post-fix build below it is a preview that still reports a 0.7.5 version, so it is conservatively treated as below the floor, which costs a preview build its projection and never lets an unfixed build through.
The 2026-08-05 named-lab cross-version probe started a server from Herdr 0.7.5 and queried it with the installed 0.8.0 client; status reported client version 0.8.0 protocol 19, server version 0.7.5 protocol 17, server running true, and server compatible false.
That ordinary post-upgrade shape proves the running server owns the focus behavior, so the unconfigured default composes client and selected-server verdicts conservatively and rechecks after server ensure before publishing a journal or creating a workspace.

Refresh this table with the opt-in guard, which re-downloads the pinned assets, verifies their digests, and fails naming any release whose reported version, protocol, or verdict has moved:

```sh
FM_HERDR_VERSION_FLOOR_LIVE_E2E=1 tests/fm-herdr-version-floor-live-e2e.test.sh
```

The classifier itself, the config preference it composes with, and the one-warning-per-release behavior are pinned portably with no Herdr installed:

```sh
tests/fm-backend-herdr.test.sh
```

Observed guarantees: every measured release classifies as the table records; either the protocol or the version signal alone carries an at-or-above verdict, and each divergent pair flips once the carrying signal is removed; client and running selected-session server verdicts compose conservatively, an unreadable server-running state and losing both release signals report indeterminate and fall back flat, the default is rechecked after server ensure before projection publication, an unconfigured home is projected only at or above the floor, an explicit `on`, including the historical empty opt-in file, is honored below it, and the below-floor warning is emitted once per home per detected release rather than once per spawn.

The whole real-Herdr lane was run on 2026-08-05 against both the CI-pinned Herdr 0.7.4 protocol 16, which is below the floor, and Herdr 0.8.0 protocol 19, which is at it:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh bin/fm-test-run.sh --lane real-herdr-gated
```

Both runs reported `family=real-herdr-gated count=11 failed=0`.
The projection suite's unconfigured-home case is release-aware rather than pinned to one outcome, so it proves the projected default on 0.8.0 and the flat fallback with its naming warning on 0.7.4:

```text
ok - real Herdr lab: a home that configured nothing is projected by default on herdr 0.8.0
ok - real Herdr lab: a home that configured nothing falls back flat on below-floor herdr 0.7.4 with one naming warning
```

Every other case in that suite uses an explicit opt-in or opt-out, so the floor leaves them unchanged on both releases.

Direct lab probes on 2026-07-28 established the removal rules the emptying-close plan relies on, each verified with `workspace list` focus reads around one mutation in a guarded `fm-lab-` session:

- An explicit `pane close` that emptied a non-focused workspace moved focus off the focused workspace in both before-focus and after-focus geometries.
- Ending a workspace's lone shell preserved the focused workspace exactly when the dying workspace sat behind it or the focused workspace was last, and moved focus to the focused workspace's right neighbor otherwise.
- The production focus-preserving close in the dangerous geometry repositioned the doomed workspace, ended its proved shell, and left every concurrent focus sample on the exact anchor with no corrective `tab focus` issued.

Two real-hardware conditions were required for the pane-death path to engage and are now encoded in the adapter and its unit fixtures: BSD `ps` reports a login shell's `comm` as `-zsh`, and an idle shell transiently hosts a prompt helper (starship) as a second foreground process immediately after a `workspace.move` relayout, which the bounded settle window absorbs.

The rules match the v0.7.5 tag source (`close_selected_workspace` reassigns focus from the closing workspace's index; `handle_pane_died` only clamps the stale focused index), and the upstream default branch resolves both paths by workspace id (PR #1877, commit `165dca45`, for the explicit close; PR #1912, commit `a979916`, for pane death), so the plan degrades to a harmless reorder-then-remove once a release carries them.

The full projection and restored-shell suites were re-run on 2026-07-28 on Herdr 0.7.5 with the updated close path; the presentation suite completed with `real Herdr lab validation completed on Herdr 0.7.5 with the default-session tripwire intact`, and the restored-shell cleanup guarantee above was unchanged.

The teardown-level record-retention gate was verified on 2026-07-28 with metadata fixtures and a live contending lock holder:

```sh
tests/fm-teardown.test.sh
tests/fm-backend-herdr.test.sh
```

Observed guarantees: a contended presentation lock refused the teardown before the isolated copy was returned, with the task branch, every durable record, and the endpoint intact and no pane close attempted; the retry after the contention cleared returned the copy, closed the pane under the lock, and removed the records; an unknown structured-presence result after an attempted projected close retained the journal and every record with a nonzero exit; and every presence-gate mode accepted only a structured not-found as gone.

The same fixtures verified three further boundaries on 2026-07-29: missing or malformed endpoint identity and an unparseable pane presence refused record removal with everything retained; the SIGKILL escalation re-read the exact pane's process information and refused to signal when a different shell pid owned the pane, falling back to the plain close with the original process untouched; and a reposition whose removal then failed on every path restored the exact original workspace order through a second verified move and reported the close as failed.

The teardown fixture was re-run on 2026-07-31 after extending the same fail-closed boundary through forced secondmate cleanup, including recursive cleanup of a nested secondmate whose Herdr grandchild close remains unconfirmed.

Observed output:

```text
ok - forced secondmate teardown preflights every Herdr child before cleanup mutation
ok - forced secondmate teardown retains Herdr child identity until exact pane disappearance
ok - forced teardown retains a nested secondmate home and its grandchild's Herdr identity when the grandchild close is unconfirmed
```

### Composer and operational input

Real captures verified these active distinctions:

- Claude and Codex use bare `❯` and `›` agent composers.
- Dim or faint suggestion text is ghost content, while normally styled text is pending input.
- On a kiro pane only, a near-achromatic truecolor run up to `FM_COMPOSER_GHOST_GRAY_LUMA_MAX` is ghost content, while a chromatic glyph at similar luminance stays real; every other harness keeps the shared ceiling, so Claude's grey slash-command input stays typed input.
- On a kiro pane only, a 256-colour index is luminance-tested as ghost content inside the 232-255 greyscale ramp, whose RGB is fixed by definition; every other index, and every index on another harness, is not tested at all.
- On a real Herdr 0.9.5 pane running kiro-cli 2.35.1, the idle composer reads `empty` when the caller names `kiro` and `pending` otherwise, so the harness must be named for every kiro composer read; [Kiro CLI adapter verification](kiro.md#2026-10-29-re-verification-on-kiro-cli-2351) owns the run.
- A bare shell prompt has no safe agent-composer container and is unknown.
- Codex 0.154's idle braille starfield rows are composer furniture, with the dated Herdr evidence and refresh command in [Composer classification matrix](#composer-classification-matrix).

`tests/fm-composer-ghost.test.sh`, `tests/fm-composer-lib.test.sh`, and the Herdr composer cases pin the exact captured ANSI bytes.
The byte-exact active regression for the U+2063 operational and routed-request separators on Herdr is:

```sh
FM_SEND_MARKER_HERDR_E2E=1 \
  tests/fm-send-secondmate-marker-herdr-e2e.test.sh
```

### Native blocked event

The protocol-16 event path was measured on 2026-07-11 with Herdr 0.7.3 and Python 3.13:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-eventwait-smoke.test.sh
```

Observed output:

```text
ok - real herdr: events.subscribe capability gate passes
ok - real herdr: a driven idle->blocked transition returns the blocked record in 0.129s
ok - real herdr: the watcher fast-path enqueues a stale wake naming the task window
```

Polling remained active and is covered as the fallback for capability, connect, subscribe, and repeated reader failure.

### Agent lifecycle control

Herdr is one of the two backends whose recovery-grade agent-state classifier the control plane may trust ([agent-control.md](../agent-control.md)), so its lifecycle gating is measured against the real binary; reverified 2026-08-08 on Herdr 0.8.0, and first measured 2026-08-02 on Herdr 0.7.5 with identical results:

```sh
tests/fm-control-herdr-smoke.test.sh
```

Observed output, refreshed 2026-09-10 on Herdr 0.9.0 after the stale-registration fix (the two stale-registration lines are recorded under "Stale agent registration" below):

```text
ok - real herdr: exit on a pane with no registered agent is idempotent success
ok - real herdr 0.9.0: a gone session reads recoverable while a live pane and a malformed target do not
ok - real herdr: a drifted agent-free shell returns to its worktree and reuses the same endpoint
ok - real herdr: interrupt refuses when herdr's own agent registry reports no agent
ok - real herdr: interrupt delivers the harness's key and proves the agent survived it
ok - real herdr: no control verb removed the endpoint or the task's local copy
ok - real herdr 0.9.0: a registration Herdr keeps after its agent exits reads stale-agent and recovers as dead
ok - real herdr: exit on a pane with a stale registration is idempotent success
ok - real herdr: a stale registration no longer blocks relaunch, and the endpoint and local copy survive
ok - real herdr: an agent that does not stop fails closed instead of being reported as stopped
```

The registry read through `herdr pane report-agent` is the same source `fm_backend_herdr_agent_state` classifies, and since 2026-09-10 that registration counts as an agent only while `pane process-info` shows a harness process behind it, so the guard backs the registration with a real process named like a harness (using `fm_agent_standin` from [`tests/lib.sh`](../../tests/lib.sh)) and then stops that process, with no real harness launched.
That command is the guard that refreshes this record; run it after every Herdr upgrade rather than trusting the version above.

### Endpoint recovery classification

Measured 2026-09-10 on macOS aarch64 against Herdr 0.9.0 (protocol 22) in an isolated `fm-lab-` session.

An endpoint recorded in a session whose server is not running cannot be read by any operational call, and `status` is the one command that answers with a body instead of refusing:

```sh
herdr pane get w1:p2 --session fm-lab-never-started
herdr status --json --session fm-lab-never-started | jq -c "{running: .server.running, status: .server.status}"
```

```text
{"id":"cli:pane:get","error":{"code":"server_not_running","message":"no herdr server is running at /Users/kunchen/.config/herdr/sessions/fm-lab-never-started/herdr.sock; run `herdr session attach fm-lab-never-started` to start or attach it"}}
{"running":false,"status":"not_running"}
```

`fm_backend_herdr_agent_state` therefore settles an uninterpretable pane read with `.server.running` rather than with the `server_not_running` error code, which keeps the verdict working across the supported range: the field is present on 0.8.2 protocol 20 and 0.9.0 protocol 22 alike (measured in "Client selection" above), while the code is not.
Only that recovery-grade read is widened; the husk classifier under it stays strict, because it licenses closing panes.
Observed in the lab, in one run:

```text
live agent-free pane                 dead
endpoint in a session with no server missing
malformed target                     unreadable
```

The same run drove `bin/fm-spawn.sh --relaunch` against a real Herdr pane whose shell had been moved outside its recorded worktree: the shell was told once to return, ended in the recorded worktree, and the replacement was launched into the SAME pane, leaving one task tab.

Herdr 0.8.x is not installed on this host, so protocol-20 coverage is structural plus the adapter fixture exercising both response shapes; it is not a live result.
Refresh the live half, which fails naming the installed version, with:

```sh
tests/fm-control-herdr-smoke.test.sh
```

Observed 2026-09-10:

```text
ok - real herdr 0.9.0: a gone session reads recoverable while a live pane and a malformed target do not
ok - real herdr: a drifted agent-free shell returns to its worktree and reuses the same endpoint
```

`tests/fm-backend-herdr.test.sh` pins the logic portably by driving the two signals apart - the same failed pane read yields `missing` under a stopped server and `unreadable` under a running one - and asserts that the husk classifier still refuses on that identical read.
`tests/fm-control-herdr-smoke.test.sh` proves the Herdr-only drift recovery against a real binary in an isolated lab session.
`tests/fm-control-relaunch.test.sh` drives a tmux stub and proves that tmux retains its prior refusal without sending `cd` or any other input to the pane.
The Herdr refusal when a shell accepts the command but does not move is not exercised in this change.

### Stale agent registration

Measured 2026-09-10 on macOS aarch64 against Herdr 0.9.0 (protocol 22) in an isolated `fm-lab-` session (upstream issue #4115, duplicates #3639, #3487, #2908, #3545).

Herdr keeps an agent registration after the agent process has exited to a shell when a nested interactive shell sits under the pane's top shell, which is the crew shape `treehouse get` leaves behind.

Before the fix `fm_backend_agent_state herdr` read that state as `alive`, so `bin/fm-control.sh <id> relaunch` and `bin/fm-spawn.sh --relaunch` were refused for as long as the registration lived, which is hours.
The registration is still present after the wait, and Herdr's own `pane report-agent` leaves the same shape behind on any pane, which is what the lifecycle-control guard uses.

Two vendor facts the fix rests on, read from `fm_backend_herdr_pane_process_state`'s `pane process-info` parse:

- A harness process is attributed by argv[0] exactly as the tmux probe attributes it; a symlink named `claude` to `sleep` presents as name `sleep`, argv0 `claude`.
- Herdr creates the record with its own placeholder `agent_status` of `unknown` the moment it notices an agent, before the agent reports `idle`; that transient reads `unknown` in the pane classifier as it always did, and only a lifecycle status is subject to the process-level proof.

Subcommand presence below the 0.9.0 measurement, checked 2026-09-10 on macOS aarch64 against the pinned upstream release clients fetched from `https://github.com/ogulcancelik/herdr/releases/download/v<version>/herdr-macos-aarch64` (now redirected to `herdrdev/herdr`):

| Release | sha256 |
|---------|--------|
| 0.7.1 | `16f4653f0491ea1e7d2b46b5b02542f18e1b82e88daaf9e2900572e5bb634df8` |
| 0.7.3 | `b31345392d004ec1f1b2c821e1ad601019fa8385fe1e4c6931321eb58a920773` |
| 0.7.4 | `24992e1625dbdcb18354a59e299e4b263c312400b31396cdc07cd46ed57f24a7` |
| 0.7.5 | `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6` |

The command run against each client was `<client> pane --help`, which is client-side, session-independent, and opens no socket, and each printed the line:

```text
process-info  Show pane process information
```

This proves subcommand presence in the client only, not the server response shape, which is measured only on 0.9.0 above.

`tests/fm-control-herdr-smoke.test.sh` proves the same shape through the control plane with no harness launched (the two `stale` lines under "Agent lifecycle control" above): a registration over a real agent-named process reads `alive`, stopping that process makes the pane read `stale-agent` and recover as `dead` while `agent get` still reports the record, `exit` then reports `already-stopped`, and `--relaunch` reuses the same endpoint with the local copy intact.
`tests/fm-backend-herdr.test.sh` pins the logic portably with canned `process-info` bodies over real processes, driving the signals apart: the identical shell-only foreground reads `stale-agent` for a childless shell and `live` when an agent-named process is still a descendant of that shell, a `working`, `done`, or `blocked` record over a shell-only pane reads the same as `idle`, an unreadable process view reads `unknown` and refuses husk closing, a transient prompt helper beside the shell settles into `stale-agent` on the next shell-only sample while a foreground that never settles within the bound still reads `live`, and `busy_state` verifies a `working` record before reporting busy.
`tests/fm-crew-state.test.sh` pins the recovery classifier: a stale registration over a shell-only pane reports agent gone rather than alive or unreachable, and a stale `working` record never reports the pane working.
A stale-registration pane is never a husk: create, reclaim, presentation recovery, and session cleanup keep refusing it, and only recovery reuses it.

### Away-mode transport

The daemon injection transport into a live composer keeps its coverage in `tests/fm-afk-inject-herdr-e2e.test.sh`, and the dedicated Herdr daemon workspace topology is covered by `tests/fm-afk-launch.test.sh` and preserves the captain tab's pane count.

## Orca

Real readiness was verified against `/usr/local/bin/orca` with `/Applications/Orca.app` bundle version 1.4.116.

```sh
orca status --json
```

Observed fields:

```text
result.runtime.reachable=true
result.runtime.state=ready
```

`orca terminal create --json` returned `result.terminal.handle`.
`orca worktree create` returned `result.worktree.id` and `result.worktree.path`.
Speculative bare ids and nested terminal fields were deliberately rejected.

```sh
tests/fm-backend-orca.test.sh
tests/fm-backend.test.sh
tests/fm-bootstrap.test.sh
```

The fake-Orca suite covers readiness, registration, create response parsing, metadata routing, popup-safe submit, and path-matched release refusal.

### Orca environment source

The environment source was verified on 2026-10-14 on macOS 15.6.1 with tmux 3.6a, Bash 5.3.20, Bash 3.2.57, and zsh 5.9.

```sh
bash bin/fm-test-run.sh tests/fm-spawn-orca-worktree.test.sh
PATH="<dir with bash -> /bin/bash>:$PATH" /bin/bash bin/fm-test-run.sh tests/fm-spawn-orca-worktree.test.sh
```

Both runs passed with `FM_TEST_SUMMARY total=1 failed=0`.

The real-tmux case uses a private socket and synthetic values.
Without `tmux -u`, tmux's non-UTF-8 client output sanitized a multiline UTF-8 value; with it, the value survived unchanged under absent and C locales through sh, Bash, and zsh.
`show-environment -t =<session>` reported the automatically populated `SSH_AUTH_SOCK`, which the snapshot excludes because only allowlisted names are read.
A name present only in the server-global environment, or only as text inside another value, was refused.
The fake-Orca cases execute the real staged launch file under synthetic personal credentials and cover refusal before allocation, file privacy and deletion, deletion-failure refusal that keeps the interactive pane with and without errexit, reclaiming a launch file the pane never ran while the terminal stays open, reclaiming it when HUP, INT or TERM interrupts the spawn after the file is published but before the launch command is sent, during the consume wait, or between text delivery and Enter, a pane that wins the deadline unlink race, and the missing-source warning.

## Codex App host tools

A reusable Desktop host-tool smoke ran on 2026-07-06 against Codex Desktop bundle version 26.623.101652, build 4674, bundle id `com.openai.codex`.
Local paths and task-specific ids are intentionally not retained here.

The host-tool sequence was:

1. list a saved project;
2. create a Desktop-owned worktree thread;
3. recover and read the thread while active and after completion;
4. verify the thread appended a Firstmate status line and wrote its report;
5. send a follow-up to the same thread;
6. read the completed follow-up;
7. archive the exact thread;
8. read the archived transcript with state `notLoaded`.

Observed guarantee: a Desktop-owned thread can write Firstmate lifecycle files when the prompt provides an authorized absolute path, and create, send, read, and archive work at the Desktop host-tool layer.
The missing guarantee remains a supported shell-callable bridge that lets Firstmate perform those operations against the same visible Desktop endpoint.
App-server partial methods and raw socket experiments do not satisfy that bridge contract.

## Cursor Agent CLI

Cursor runs crewmate, scout, secondmate, and primary work; [`supervision.md`](supervision.md#cursor-primary-park-2026-08-13) owns the primary evidence.
The evidence below was produced on 2026-08-11 against the installed signed CLI on macOS 26.5.2 arm64 with tmux 3.6a, running as `kunchenguid`, and extended on 2026-08-13 with the tmux composer verdict below.

- Binary: `~/.local/bin/cursor-agent`, canonicalizing into `~/.local/share/cursor-agent/versions/2026.08.11-e8db854/cursor-agent`.
- Version: `cursor-agent --version` reported `2026.08.11-e8db854`, and `cursor-agent status` reported a logged-in account.
- Both installed names, `cursor-agent` and the legacy alias `agent`, resolve into that same versioned install tree.

Resolution prints the STABLE launcher rather than the canonical target, because the canonical path carries a version the CLI replaces on its own auto-update.

### Process identity

`#{pane_current_command}` and `ps -o comm=` disagree for cursor, which is why identity reads both:

| Source | Observed value |
| --- | --- |
| `#{pane_current_command}` | `node` |
| `ps -o comm=` | `/Users/<user>/.local/bin/cursor-agent` |
| child argv | `.../bin/cursor-agent --use-system-ca .../versions/2026.08.11-e8db854/index.js --trust --yolo` |

`node` matches no harness name pattern, so a cursor pane is identified from Cursor's own name or install tree in the path or argv[0].
An unrelated `node` or `agent` matches neither and classifies `other`, which the liveness callers fold into `ambiguous` rather than `dead`.
A live cursor pane returned `alive`; a plain shell pane in the same run returned `dead`.

### Environment markers and detection ordering

Read from the live agent process and from a tool subprocess it spawned:

| Marker | Where observed |
| --- | --- |
| `CURSOR_INVOKED_AS=cursor-agent` | the agent process itself, and its children |
| `CURSOR_AGENT=1` | child/tool processes only |
| `CURSOR_CONVERSATION_ID=<uuid>` | child/tool processes |
| `AGENT_TRANSCRIPTS=<projects-root>/<slug>/agent-transcripts` | child/tool processes |

Cursor does not clear an inherited `CLAUDECODE`, so ordering decides the verdict within the marker layer.
With both markers set and ancestry silent, `bin/fm-harness.sh` reports `cursor`; with `CLAUDECODE` alone it still reports `claude`.
[Harness detection precedence](#harness-detection-precedence) owns what happens when a structural ancestor of another harness is present, which outranks either marker.

### Composer

Cursor's composer is a BARE row whose prompt glyph is `→` (U+2192); there is no border.
Its idle placeholder is `Plan, search, build anything` in a fresh session and `Add a follow-up` after a completed turn.

The styled capture of an idle composer row was:

```
ESC[48;2;21;21;21m ESC[2m→ ESC[0;7mESC[48;2;21;21;21mPESC[0;2mESC[48;2;21;21;21mlan, search, build anythingESC[0m
```

The glyph and the placeholder tail are dim (SGR 2), but the cell under the terminal cursor is reverse video (SGR 0;7).
Reverse video is neither dim nor a dark foreground, so ghost stripping leaves a lone `P` and an idle composer read `pending` before the fix.
After teaching the shared classifier the glyph, both placeholders, and the plain-row remnant rule, the same captures read `empty` on the styled cursorless backends, while real typed text - including text typed to exactly match the placeholder - still read `pending`.
An unstyled capture has no ghost-strip proof and correctly stays `unknown`.

#### tmux composer verdict, corrected 2026-08-13

The 2026-08-11 record that a Cursor pane's tmux composer verdict is `unknown` in every state described the cursor-ANCHORED read, which remains true: `#{cursor_y}` was 25 with `#{cursor_flag}` 0 on an idle pane, pointing below the footer, so tmux's cursor row is not a composer locator for Cursor.
Read cursorlessly, the same live capture classifies correctly, so the composite verdict is no longer `unknown`:

```text
cursor_y=25  cursor_flag=0
with-cursor : unknown      cursorless : empty     (idle composer)
with-cursor : unknown      cursorless : pending   (real typed text, not submitted)
with-cursor : unknown      cursorless : unknown   (agent exited to a shell)
```

`bin/fm-tmux-lib.sh` therefore reclassifies cursorlessly only when the pane's foreground process group is provably Cursor, so every other harness keeps the strict blank-cursor-row posture.
That supplies the genuine composer-empty proof required for away-mode escalation delivery.
A live injection through `bin/fm-supervise-daemon.sh`'s own `inject_msg` into a real Cursor pane returned 0 and the pane processed the typed `FIRSTMATE_OP: v1 away-supervisor:` escalation.

`tests/fm-tmux-agent-liveness.test.sh` pins this with real processes and no Cursor installed: it asserts the cursor-anchored source is blind, that the composite still reads `empty` idle and `pending` with typed text, that an identical screen stays `unknown` when the pane is not Cursor, and that a stale Cursor screen over a dead shell never reads `empty`.

#### tmux composer verdict, fully dim placeholder 2026-10-21

On 2026-10-21 the same idle shape was captured again from cursor-agent 2026.10.19-6bbf2c4 on tmux.
`#{cursor_y}` was still below the footer with `#{cursor_flag}` 0, and `fm_tmux_pane_is_cursor` still matched `~/.local/bin/cursor-agent`.
The placeholder row had changed: `→ Add a follow-up` was one SGR 2 run on background `48;2;42;44;57`, with half-block rules above and below and no reverse-video cell.
Ghost stripping emptied that row, and the empty-content guard treated any plain row longer than a lone glyph as `unknown`, so the composite stayed `unknown` and relaunch and exit refused.
The plain row is still the anchored placeholder, so that guard now reads it `empty`.
Bright text, including text typed as exactly `Add a follow-up`, is not stripped and stays `pending`.

```text
composer row : ESC[48;2;42;44;57m ESC[2m→ Add a follow-upESC[0m
before       : idle composite unknown    fm_backend_composer_state unknown
after        : idle composite empty      fm_backend_composer_state empty
typed        : bright `Add a follow-up`  pending
```

`test_matrix_cursor_fully_dim_placeholder` in `tests/fm-composer-lib.test.sh` pins this shape and asserts the row ghost-strips to empty, so the older reverse-video remnant path cannot satisfy it.
`tests/fm-tmux-agent-liveness.test.sh` repeats the idle `empty` and typed `pending` verdicts through a real pane whose foreground binary is `cursor-agent`.
Refresh the Cursor liveness evidence with:

```sh
FM_HARNESS_LIVENESS_DRIFT=1 bin/fm-test-run.sh tests/fm-harness-liveness-drift-live-e2e.test.sh
```

On 2026-10-22 that command classified cursor-agent 2026.10.22-27dcf5f alive at `comm cursor` strength.

### Busy state

Cursor writes a per-conversation transcript at `<projects-root>/<workspace-slug>/agent-transcripts/<conversation-id>/<conversation-id>.jsonl`.
Each turn is bracketed by a `role:user` open and a typed `{"type":"turn_ended","status":...}` close.
Observed closes: `success` for a completed turn, and `aborted` with `"error":"User aborted/interrupted manually."` after a single Escape.

The trailing close landed 0 seconds after the pane's busy footer cleared on a normal turn.
The transcript does NOT accumulate one close per turn, so a count of closes is not a progress signal; only the trailing record is.
After an interrupt the aborted close was observed within seconds in some runs and not within twenty seconds in others, so `bin/fm-control-lib.sh` deliberately claims no cancellation acknowledgement for cursor.

Binding never reconstructs cursor's workspace-slug directory name, which collapses path separators.
Cursor records the exact absolute workspace path in each project directory's `.workspace-trusted`, and the binding matches on that value.

### Rendered busy token, delivery only

Mid-turn the pane showed a braille spinner plus a verb, and `ctrl+c to stop` on the composer row; both the verb line and that token were absent the instant the turn ended.
The same version rendered `Working` in one turn and `Running` in the next, so the TOKEN is matched and the verb is not.
This row is a delivery guard for submit acknowledgement only; recorded worker state comes from the transcript fold.

### Launch, lifecycle, and skills

| Fact | Observed |
| --- | --- |
| Workspace trust | `--trust` suppressed the prompt; `--yolo` alone did NOT, and the prompt blocks a fresh worktree |
| Autonomy | `--yolo` (alias of `--force`); the footer renders `Run Everything` |
| Worktree | `-w/--worktree` allocates a SECOND worktree under `~/.cursor/worktrees` and is never passed |
| Effort | no effort flag exists; requested effort stays in task metadata |
| Interrupt | single Escape; the pane showed `Cancelled` and the composer returned to its placeholder, so no clear key is needed |
| Exit | `/exit` |
| Skill invocation | `/<skill>`; cursor discovers firstmate's user-level skills, and `/no-mistakes` autocompleted with firstmate's own description and invoked the skill |
| Slash popup | real: the first Enter closes the popup and a SECOND Enter submits, covered by the submit core's retried Enter |

### End-to-end

A throwaway scout was spawned through `bin/fm-spawn.sh --scout --backend tmux` on a real cursor worker and driven to completion:

1. the launch delivered its brief positionally and the agent executed it;
2. `state/<id>.cursor-session` was written with the task worktree;
3. the transcript fold read `busy` mid-turn and `idle` after it;
4. `bin/fm-send.sh` delivered a steer through the then-current typed path and exited 0;
5. `bin/fm-control.sh <id> interrupt` cancelled a running turn;
6. `bin/fm-control.sh <id> exit` stopped the agent;
7. `bin/fm-teardown.sh` refused until the scout's report and decision gate were satisfied, then removed the session record.

### Herdr backend

The tmux run above is the reference; this section is the separate Herdr proof, produced on 2026-08-12 against Herdr 0.8.0 (client and server, protocol 19) and the same signed `cursor-agent` 2026.08.11-e8db854 on macOS 26.5.2 arm64.
Every step ran inside an isolated `fm-lab-` session provisioned by `bin/fm-herdr-lab.sh`, launched from a neutral parent outside any Herdr pane, with the live default session's pane count checked before, during, and after; it stayed at 7 throughout.

**Herdr's native agent state is unusable for Cursor.**
A 60-sample probe of `agent get` across a full turn reported `agent_status=blocked` in every state - idle, mid-turn, and after.
The typed submit path's idle baseline is therefore structurally unreachable for Cursor, and every typed send falls into the composer branch.

| Pane state | Composer verdict | Rendered footer |
| --- | --- | --- |
| Idle | `empty` | no busy token |
| Text typed, not submitted | `pending` | no busy token |
| Mid-turn | `pending` (placeholder plus `ctrl+c to stop` on one row) | `ctrl+c to stop` |

Herdr draws the composer's rules with the half-block glyphs U+2584 and U+2580 rather than the box-drawing family.
Before those were taught to the shared edge detector, a bare composer's wrap region ran through its own closing rule and swallowed the model and path footer, so an idle pane read `pending`.
Measured as an A/B on the same live pane, the pre-fix classifier returned `pending` and the current one returned `empty`.

The idle fix alone did not confirm typed delivery, because the composer branch reads the mid-turn row instead.
With the rendered-footer transition in place, a typed-plane `bin/fm-send.sh` invocation exited 0 and the steer executed in the pane; the same send previously exited 1 with `delivery unconfirmed; verdict=pending` on a message that had actually landed.

The rest of the lifecycle was driven end to end on that worker:

1. `bin/fm-spawn.sh --scout --backend herdr` placed the worker and it executed its brief;
2. the transcript fold read `busy` mid-turn and `idle` after, unchanged from tmux, so the recorded worker state is backend-agnostic;
3. `bin/fm-control.sh <id> interrupt` reported `cancel=unconfirmed` by design and the pane showed `Cancelled`, with the footer and the fold both returning to idle;
4. `bin/fm-control.sh <id> exit` stopped the agent through the slash popup and the pane returned to its shell;
5. `bin/fm-teardown.sh` refused until the scout's report and decision gate were satisfied, then removed the session record and returned the worktree.

Other harnesses on Herdr are unaffected by the edge-detector change.
All seven live panes of the running default session - one Pi, four Claude, two plain shells - classified identically under the pre-fix and current classifiers.

**Typed-submit confirmation is verified on tmux and Herdr only.**
Orca's submit core never consults the busy footer, so a typed-plane Cursor send there lands but `fm-send` reports delivery unconfirmed and exits non-zero; ordinary text steers ride the durable inbox and exit 0 at enqueue.
Teaching that shared core the same transition is deliberately separate work, because it changes the submit path for every harness on Orca and needs its own live validation there.

The portable regression is `tests/fm-cursor-harness.test.sh`, the composer captures are pinned in `tests/fm-composer-lib.test.sh`, and the Herdr submit and footer behavior is pinned in `tests/fm-backend-herdr.test.sh`.
Refresh this harness-dependent proof before accepting a cursor upgrade:

```sh
FM_HARNESS_LIVENESS_DRIFT=1 bin/fm-test-run.sh tests/fm-harness-liveness-drift-live-e2e.test.sh
```

## Supervision branch away posture

### 2026-09-18 away posture parks main

The fleet-record, decision-answer, return, and merge suites were run on macOS 26.5 arm64 (Darwin 25.5.0).
No model was selected or prompted and no provider call was made.

```sh
bin/fm-test-run.sh tests/fm-branch-supervision.test.sh tests/fm-send-resolve-key.test.sh tests/fm-afk-return.test.sh tests/fm-pr-merge.test.sh
```

```text
ok - under the away-posture record every actionable row is offered to the branch while broken-queue wakes and watcher-failure alarms still reach main
ok - under the away-posture record the wake carries the verbatim read-back tail, claims every row, opens no processing turn, cancels a pending request, and presents the accumulated rows after archive
ok - an accepted away-only wake rejects after archive, while a drained task-local wake stays a quiet no-op
ok - a claimed heartbeat row on a non-heartbeat away wake lifts task scoping for the fleet report
ok - the away-posture record relocates the PR merge and a spawn under the spend cap to the branch, never local landing, and only while confirmed and valid
ok - relocated branch spawn admits only already-queued dispatchable work, including on a manual-backend home
ok - the away spend cap is rechecked under the task-set lock so concurrent spawns cannot both publish
ok - fm-send --resolve-key: a decision answer refuses the attended branch before sending, a blocked: key stays steering, and the away-posture record relocates the answer
ok - under the away-posture record the branch merges a granted green task, is held without a grant, cannot waive a red check, and is refused at the partition while attended
```

Every record read in those regressions ultimately goes through the real `bin/fm-afk-contract.sh`, with fixture wrappers used only to archive at deterministic call boundaries; an absent record, an archived record, and an invalid record are proven to restore attended guarded-action behavior rather than being assumed to.

### 2026-09-20 the away words execute

The away-record owner, launch, return, merge, branch-supervision, contributions, and merge-poll security suites were run on macOS 26.6.2 arm64 (Darwin 25.6.0), Node v24.14.1, after the away record became the captain's words alone (version 2, with version 1 still readable) and the per-task merge-grant list retired.
No model was selected or prompted and no provider call was made.
The 2026-09-18 entry above records the retired grant model's merge matrix; the lines below supersede it for the merge gate.

```sh
bin/fm-test-run.sh tests/fm-afk-contract.test.sh tests/fm-afk-launch.test.sh tests/fm-afk-return.test.sh tests/fm-pr-merge.test.sh tests/fm-branch-supervision.test.sh tests/fm-contributions.test.sh tests/fm-pr-check-security.test.sh
```

```text
ok - the read-back renders the words verbatim beside the expected return, spend cap, and reach line
ok - one enter call writes a version 2 record, announces hold-for-return only, reads it back without asking for a go, and every read subcommand reflects it
ok - the retired propose, confirm, and --proposal inputs are refused by name and write nothing
ok - retired clause fields, --grant, and the clause and grant subcommands are refused by name
ok - a version 1 record validates, reads its words and scalars with the clause and grant sections ignored, refreshes untouched, and archives
ok - new words over a live version 1 record archive it and write version 2 with the same session start
ok - enter: the retired --grant flag is refused by name and leaves the standing record alone
ok - the return brief renders health, the words with the session account, waiting, could-not-fix, handled, and cost from durable records, and the gate shrinks to what the away session could not fix
ok - while the away-posture record exists any green merge lands under away authority, yolo or not, and attended merges stay untagged
ok - under the away-posture record the branch merges a green task, is refused on a red check with or without --allow-red, and is refused at the partition while attended
ok - the away record does not bypass red checks, and a recorded pr= must match the URL
ok - no away-record archive or replacement lands between the authority read and the merge
ok - a record made unreadable before the merge's own authority read refuses the merge
ok - queued merges retain their away authority after captain return
ok - branch prompt is byte-stable across homes, cwd, timezone, and time, above the cache floor
ok - under the away-posture record the wake carries the verbatim read-back tail, claims every row, opens no processing turn, cancels a pending request, and presents the accumulated rows after archive
```

The merge suite and the security suite dominate the wall time.

## Busy inbox escalation

Verified at `2026-10-03T19:20:07Z` on commit `23b0232908a5adc7fbf7339ef48c34a091a7a799` with Claude Code `2.1.288 (Claude Code)` on Herdr `0.9.1`, protocol `22`, in a named isolated lab session through `bin/fm-herdr-lab.sh`.
`bin/fm-task-inbox-lib.sh` owns the durable busy-deferral budget.

A real Claude worker opened an `AskUserQuestion` panel, and Firstmate's `UserPromptSubmit` hook reported busy.
Four due inbox checks using the original `origin/main` watcher at `1f3e769616fdf9f31f85f4c3e6a9f71606634238` against that live pane each read `busy=yes` and added zero wakes.
With `FM_TASK_INBOX_GRACE_SECS=0 FM_TASK_INBOX_BUSY_MAX=2`, two distinct processes sourcing the fixed watcher and calling `inbox_steer_check` against the same pane produced one wake containing `stuck-busy after 2 consecutive busy-deferred due doorbells`.
A third check left exactly one wake total; the question panel remained open and the instruction remained unhandled.
Lab teardown completed with exit `0`, including the default-session tripwire.
The zero grace accelerates only the experiment; the normal grace remains unchanged.
Without Firstmate's hooks, Herdr reported the question panel as `blocked`, which did not classify as busy; that is a different path and does not establish this regression.

This live proof covers the watcher and queue boundary; it does not establish live daemon-consumer delivery.
`bin/fm-test-run.sh tests/fm-daemon.test.sh` exercises that consumer routing separately with portable regressions for busy escalation and busy-bookkeeping failures in away and quiet mode.
Repeat the hooked-worker check above before publication if watcher or task-inbox busy code changes; `bin/fm-test-run.sh tests/fm-task-inbox.test.sh` refreshes the portable ladder regressions.

## OpenCode 2 launch and brief delivery

Verified on 2026-10-15 on Linux x86_64 against OpenCode 2.0.11 and 2.0.22, each installed into a scratch npm prefix with scratch `HOME`, XDG directories, and `OPENCODE_DB`, while the host's global OpenCode 1.18 stayed in place.

The token-free native plugin fixture passed on both releases:

```
$ FM_OPENCODE_LIVE_BINS="<2.0.11>/bin/opencode <2.0.22>/bin/opencode" tests/fm-opencode-primary-live-e2e.test.sh
ok - OpenCode 2.0.11 loaded all five V2 Firstmate plugins
ok - native shell execute.before rejects persistent-cd before execution
ok - native terminal event admits a turn-end guard follow-up
ok - native interrupted turn retains watcher supervision
ok - native failed turn retains supervision and startup remains exactly once
ok - OpenCode 2.0.22 loaded all five V2 Firstmate plugins
(every other fixture case also passed on both releases)
```

The native fixture was re-run on 2026-10-15 after the seatbelt was narrowed to the shell tool's `{tool, input.command}` `execute.before` payload, and it passed on both 2.0.11 and 2.0.22.
Its loopback provider issues a real `shell` tool call, and the persistent-cd and watcher-redirection cases assert the tool fails with the plugin's own reason and writes no escape file, which proves that payload shape live.

A standalone TUI on both 2.0.11 and 2.0.22 showed the composer exit behavior `bin/fm-control.sh` relies on.
With leftover composer text, the first Ctrl-C only clears the text and a second Ctrl-C exits.
Ctrl-U clears the composer, and one Ctrl-C then exits.

A tmux pane launching `opencode --standalone --prompt '<brief>'` against a loopback provider showed the brief-delivery difference the post-launch gate handles:

```
2.0.11 after 20s: provider_requests=0 composer=pending
2.0.11 after one Enter: provider_requests=2
2.0.22 after 20s: provider_requests=2 composer=pending
```

On 2.0.11 the brief stays unsent and the shared composer classifier reads it as pending, so the gate's single Enter is sent and starts the turn.
On 2.0.22 the brief is submitted on its own, yet the composer still reads pending, which is why the gate treats the worker's busy-state plugin record as proof of delivery and the composer only as a veto on the Enter.
`opencode debug config` on 2.0.11 normalized the launch's legacy `{"permission":{"*":"allow"}}` into an allow-all `permissions` rule; the same command printed no configuration on 2.0.22, so on 2.0.22 the legacy shape rests on the earlier 2.0.21 verification recorded in the OpenCode harness reference.
`tests/fm-spawn-dispatch-profile.test.sh` pins the gate's outcomes portably: an auto-submitted brief gets no extra Enter, a prefilled brief gets exactly one, a composer that reads unknown before it draws gets its one Enter only once it reads pending, a composer that only reads unknown gets its one Enter at the submit deadline, and a turn that never starts fails the spawn.

## OpenCode 1 compatibility of the dual-export plugins

Verified on 2026-10-15 on Linux x86_64 against OpenCode 1.15.7, 1.18.20, and 1.18.31, each installed into a scratch npm prefix and run against a scratch `FM_HOME`.
1.15.7 and 1.18.20 predate the V1 object entrypoint (`{ id, server }`) that OpenCode accepts from 1.18.29, so they exercise the named-export path of the five primary plugins; 1.18.31 exercises the object path.

A copy of this checkout whose five `fm-primary-*.js` factories each append one line to a log when invoked ran one `opencode run` turn per release, and every plugin factory ran exactly once on all three:

```
opencode 1.15.7 plugin factory invocations:
      1 fm-primary-cd-check
      1 fm-primary-pretool-check
      1 fm-primary-sessionstart-nudge
      1 fm-primary-turnend-guard
      1 fm-primary-watch-arm
(1.18.20 and 1.18.31 printed the same five counts of 1)
```

A persistent TUI per release, with the watch-arm plugin removed from that copy so no watcher could arm and one task in flight in its home, answered one prompt; the turn-end guard queued exactly one follow-up and did not fire again after the model answered it:

```
user|Respond exactly OK. ...
assistant|OK
user|⁣FIRSTMATE_OP: v1 turn-end-guard: TURN WOULD END BLIND - supervision is off. ...
assistant|NOTED
(identical on 1.15.7, 1.18.20, and 1.18.31)
```

The credentialed watcher-continuity half of the live e2e passed on 1.18.20 and 1.18.31: the plugin started the first watcher after idle, started and ledger-linked a successor after the actionable close, the model drained and settled, no turn-end guard fired, and the model never ran the arm itself.

```
$ PATH=<release>/bin:$PATH FM_OPENCODE_LIVE_E2E=1 tests/fm-opencode-primary-live-e2e.test.sh   # Ahoy sections skipped
ok - OpenCode 1.18.20 live E2E covered native Ahoy first/later messages, near misses, and watcher continuity
ok - OpenCode 1.18.31 live E2E covered native Ahoy first/later messages, near misses, and watcher continuity
```

The run is pinned to the named release because the test now launches its TUI panes through the resolved `opencode` path; it previously ran whatever `opencode` the panes' login shell found.
The full run's native Ahoy cases depend on the model's own choices and failed with the `opencode-go/deepseek-v4.1-flash` model used here (1.18.20 took Bearings on a later `/ahoy`; 1.18.31 never ran session start in the later-message setup); the unchanged test on the default branch failed at the same 1.18.31 step with that model, so those failures are not from this change.

A real `bin/fm-spawn.sh --scout --harness opencode --model opencode-go/deepseek-v4.1-flash` in a private tmux server recorded `opencode_version=1.18.20` (and `1.18.31` on the second release), launched the worker as `opencode --model opencode-go/deepseek-v4.1-flash --prompt <brief>` with no `--standalone`, and the worker answered its brief.
`bin/fm-control.sh <task> exit` then resolved the typed `/exit` from that recorded major and returned both panes to the shell.

## Native Codex supervision park

Verified on 2026-10-19 with `codex-cli 0.163.0` on macOS arm64 in an isolated named Herdr lab.
The native TUI fired project SessionStart and asynchronous Stop hooks, and `codex queue --thread` delivered input to the embedded `--no-daemon` session.
[Supervision verification](supervision.md#codex-native-model-free-park-2026-10-19) records the commands, ten-minute provider-call comparison, real check delivery, input interrupt, park-death recovery and native-exit cleanup.
This verifies the primary-session park, not a worker busy-state classifier or a Codex dialog-mirror writer.
