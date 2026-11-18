# Supervision branch

This document covers the supervision branch: the contract under which a second actor handles fleet supervision beside the captain's chat.
The supervision host ([supervision-host.md](supervision-host.md)) runs that branch as a headless engine session beside the primary.
Maintainers changing which wakes the branch may take, how its outcomes reach the captain, or how the attended and away postures differ need it.

## Find a topic

| What you want to know | Start here |
| --- | --- |
| What the branch handles and what stays on main | [Overview](#overview) |
| Which file owns each part of the design | [Components and their owners](#components-and-their-owners) |
| How a captain-facing event whose wake was lost still surfaces | [Lost-wake outcome backstop](#lost-wake-outcome-backstop) |
| What the branch sees of the captain's conversation | [How the branch knows what the captain said](#how-the-branch-knows-what-the-captain-said) |
| How outcomes are classified, shown, and acknowledged | [Two-stage noise filter](#two-stage-noise-filter) |
| How fleet-wide heartbeat reviews are routed | [Heartbeat routing](#heartbeat-routing) |
| Prompt caching and the byte-stable prefix | [Cost model and the byte-stable prefix](#cost-model-and-the-byte-stable-prefix) |
| What changes while the captain is away | [Postures](#postures) |
| Which tests pin this contract | [Verification](#verification) |

## Overview

The supervision branch is a second LLM actor beside main (the captain's chat) in one firstmate home.
On a home that runs the supervision host, the host owns the watcher cycle and hands the wakes the branch may take to a headless engine session.
[supervision-host.md](supervision-host.md) owns where the host runs, in which postures, and its mechanism.

### What the branch handles while attended

Where the host runs attended, the branch handles two kinds of work:

- Eligible task-local rows from ordinary actionable wakes.
  A row is one queued wake entry.
- Heartbeat scans that the cheap bash-level scan flags as possibly captain-relevant.

Some wakes stay on main:

- Ordinary main-only rows remain on main even when eligible task-local rows share their queue.
- A decision-owned signal or stale trigger keeps its entire coalesced trigger batch on main.
- An unresolvable row makes the scan unsafe and returns the whole wake to main.
- Every watcher-failure alarm also stays on main.

All of that describes the attended posture.
The away posture, recorded by `state/.afk-contract`, hands every row to the branch and parks main (see "Postures" below).

### How outcomes reach main

Every handled event lands in the durable outcome store before anything else sees it.
While attended, a captain outcome wakes main once, and main's drain presents it until main acknowledges it; [supervision-host.md](supervision-host.md#captain-outcomes) owns that path.
While away, captain outcomes wait in the store for the return.

### Design source

The design source is the captain-approved forked-supervision architecture board.
That board is a captain-private fleet record: a self-contained HTML explainer with the measured cache and judgment evidence.
This document records the shape it landed as, and the delivering PR cites the board artifact itself.

### Scope

In a home with no branch state, the bash-side additions remain inert (`tests/fm-branch-supervision.test.sh`).
`bin/fm-lease-lib.sh` owns how a pre-existing lease is honored on any harness.
A home on any harness that already has an outcome store still receives the shared drain compatibility recovery described in [Lost-wake outcome backstop](#lost-wake-outcome-backstop).
The branch never changes which harness is primary.

## Components and their owners

| Component | Owner or rule |
| --- | --- |
| [Wake dispatch](#wake-dispatch) | `bin/lib/fm-host-dispatch.ts` owns row eligibility and the offer rule; `bin/fm-host-dispatch.mjs` is the command entry the host reads |
| [The branch itself](#the-branch-itself) | `bin/fm-supervision-host.sh` and the engine in `bin/fm-supervision-engine-lib.sh` |
| [Branch system prompt](#branch-system-prompt) | `bin/fm-branch-prompt.sh` |
| [Outcome store](#outcome-store) | `bin/fm-branch-outcome.sh` |
| [Consistency](#consistency) | `bin/fm-lease-lib.sh`, with `bin/fm-lease.sh` as the command surface |
| [Autonomy](#autonomy) | The supervision host's home gate ([configuration.md](configuration.md#supervision-host-configsupervision-host)) |

### Wake dispatch

`bin/lib/fm-host-dispatch.ts` owns row eligibility (`scopeForUnreadWake`) and the offer rule for one close (`branchOfferForWake`).
[`watcher-continuity.md`](watcher-continuity.md#per-actor-acknowledgement) owns the per-actor consume contract.

A successful row grant transfers ownership of exactly the currently branch-eligible rows to the branch.

What is never offered, or falls back to main:

- While attended, a check-kind triggering close is never offered, even when other rows are eligible.
  Check-kind closes are merge-confirmation polls, Relay mentions, credential/auth failures, and every other legitimately main-only class.
- When the branch cannot take a close (the host's attended prerequisites missing, a broken session), it keeps the wake-to-main path.
- Watcher-failure alarms always go to main, because only main can repair the watcher cycle.

Under the away-posture record, the check-kind and decision-owned exclusions lift and every actionable row is offered ("Postures" below).
The fallback and the alarms still reach main in that posture.

#### Decision-owned rows

A decision-owned event surfaced by `bin/fm-watch.sh`'s signal path gets the same treatment as a check-kind triggering close, even though it keeps the ordinary `signal` kind.
`signal_files_actionable` marks the queued payload `needs-decision:` for any of these:

- A newly surfaced `needs-decision`.
- A `captain-held` declaration surfaced through the no-verb fallback.
- A pending-reply second-mate escalation.

`scopeForUnreadWake` excludes every marked row from what the branch may claim, as well as second-mate signals classified by the span rule below.

A second mate's status log is one shared channel carrying many independently keyed decisions, so its signal row is judged by the lines presented since the last drain rather than by the whole log.
The row is excluded when one of those lines is a decision, blocked, or captain-held line, resolves a decision open just before it, or declares, in the status parser's key positions, the key of a decision still open in that log.
A resolution that closes nothing, key-less beside only keyed decisions or keyed for a key never open, stays routine.
A key-less line otherwise falls back to its verb; an unrelated open decision alone leaves a routine span eligible, while a mixed span goes wholly to main.
The status-presentation cursor bounds that span, and a missing or unmatched cursor falls back to the whole log.
Single-task crewmate signals keep their payload rule on a plain scan and the whole-log rule on the attended host's scan, and the decision fold ignores bare transition words without a colon or complete key token, matching `bin/fm-classify-lib.sh` on both crewmate and second-mate logs.

For a stale row, `scopeForUnreadWake` folds the mapped task's status log.
It excludes the row when any `needs-decision` remains open or the current meaningful declaration is `captain-held`.
An unreadable or symlinked status log fails the scope closed rather than influencing routing.

Before cross-referencing them, the offer rule resolves trigger keys and every currently unread excluded decision row to task identity.
If a task key or endpoint alias names more than one task, including a record with a missing or empty project, the metadata scan is corrupt and the entire wake stays on main rather than selecting an owner by record order.
Exact keys take precedence over the `fm-` prefix fallback, and project context comes only from the resolved task's own metadata.
A projectless owner cannot borrow another alias's project or grant routing authority.
The cross-reference then applies two rules:

- Any signal or stale trigger containing a decision-owned task goes wholly to main, including a batch that also contains routine rows.
- An unread decision for one task keeps every later signal or stale trigger for that same task on main until the decision row is read.
  This holds regardless of which key a row carries for that task: its status-file key, its `window=` alias, or its `terminal=` handle, which is what `bin/fm-watch.sh` keys an Orca task's stale rows by.

Other tasks remain independently eligible.
The wake message itself retains its existing shape, so other harness-arm scripts remain unchanged.

#### Heartbeats during dispatch

Heartbeat handling remains independent.
A fleet-wide heartbeat keeps its own all-or-nothing rule (see "Heartbeat routing" below): it takes every branch-ownable unread row or none of them.
A co-present main-owned check row no longer defers that review to main.
That row is not fleet context the branch is missing, and main is woken for it on its own triggering close.

### The branch itself

The supervision host runs each wake the branch takes as one bounded engine turn; [supervision-host.md](supervision-host.md#one-wake) owns the order, the engine conversation, and the broken-session latch.

#### Report scoping

While a signal or stale wake is open, `bin/fm-branch-report.sh` accepts only the tasks that wake's claimed rows resolve to:

- A signal row resolves by its status-log key.
- A stale row resolves through the task record naming that endpoint.

A report for any other task id, `fleet` included, is refused before the store is touched.
That way, a task remembered from an earlier wake cannot become a delivered outcome.
A heartbeat review is not scoped by task.

The branch's guarded commands never tell it to drain queued rows mid-handling.
For that actor, `bin/fm-guard.sh` keeps the queued-wakes warning silent.
An acknowledgement that consumed nothing reports that plainly, with the exact command for the current wake (`docs/watcher-continuity.md` "Per-actor acknowledgement").

### Branch system prompt

The branch system prompt comes from `bin/fm-branch-prompt.sh`.
Its header owns the byte-stable-prefix contract (no timestamps, no fleet snapshot, no per-wake content).

### Outcome store

The outcome store is `bin/fm-branch-outcome.sh`.
Its header owns the append-only format, read cursor, processed marker, and bounded per-task status-coverage indexes.

Outcomes are written to the store before they are delivered to main.
Locked session-start replay stops before the first captain row, so it cannot acknowledge that outcome through prose alone.

### Consistency

`bin/fm-lease-lib.sh` owns:

- The per-task lease contract.
- The posture-aware main-only role partition.
- The deliberate CONFUSED-AGENT-GRADE threat model these guards target.
  That threat model was captain-decided; adversarial-grade separation is out of scope and tracked as follow-up design work.

`bin/fm-lease.sh` is the command surface.

The guards are wired into these scripts:

| Scripts | Guard behavior |
| --- | --- |
| `fm-send.sh`, `fm-control.sh`, and `fm-teardown.sh` | Overlap, lease-checked, with claim serialization retained through the mutation. |
| `fm-pr-merge.sh`, `fm-merge-local.sh`, `fm-spawn.sh`, `fm-send.sh --resolve-key` for a decision key, and `fm-teardown.sh` for a second mate | Main-owned while attended; branch refused. |

A relaunch through `fm-control` stays branch-legal recovery in both postures.
Under the away-posture record, the PR merge, a fresh spawn, and a decision answer relocate to the branch behind each script's own gate.
Local-only landing and second-mate retirement never do ("Postures" below).

### Autonomy

The branch supervises every task on a home that runs the supervision host ([configuration.md](configuration.md#supervision-host-configsupervision-host) owns that gate).
No captain grant file is required.

A fleet-wide heartbeat is separately eligible only when every row other than a check or decision-owned signal/stale row is a heartbeat row or a resolvable task-local row (see "Heartbeat routing" below).
Every other fleet-wide or unresolvable wake, and every watcher-failure alarm, stays on main.

#### Pre-drain recheck

The host recomputes eligibility immediately before the engine turn starts.
It publishes the exact eligible row set to `state/.branch-eligible-rows` through `bin/fm-wake-grant.sh`.

After an independently eligible wake has already been offered, a newly-arrived main-owned row observed at that pre-drain recheck does not revoke the offer.
Instead, that row is excluded from the eligible set.
Whatever else is currently eligible still reaches the branch, and the main-owned row stays queued for main's own drain.
[`watcher-continuity.md`](watcher-continuity.md#per-actor-acknowledgement) owns the consume-side guarantee that neither actor can present or acknowledge the other's claim.

Heartbeat keeps its own all-or-nothing recheck over the rows it can claim: it takes every branch-ownable unread row or none of them.
An unresolvable task-local row still defers the whole review to main.

A producer can still append a row in the instant between that final check and drain startup.
This accepted residual follows the confused-agent-grade boundary above rather than claiming adversarial queue isolation.

## Lost-wake outcome backstop

Every main-actor wake drain checks each task's newest non-blank status event against the latest supervision-branch outcome that causally covers that task's status log.
When that event is terminal or otherwise captain-facing and remains uncovered, the drain prints it once in `STATUS OUTCOME BACKSTOP`.
It does so even if the original queue row was already acknowledged.
Routine events stay silent, and valid open decisions remain owned by `OPEN DECISIONS`.

The one-shot backstop cursor is independent from signal annotation.
A delayed signal can therefore still present its status context without repeating the recovered event.

### Bounded cost

The drain reads one fixed-size per-task outcome index instead of scanning append-only outcome history.
It inspects at most the final 64 KiB of each status log.

### Ordering limits

Status provenance added to new outcome rows distinguishes covered and genuinely later events even within one timestamp second.
Legacy outcomes predate that causal position, so equal-second migration cannot prove order.
That migration deliberately favors surfacing a plausibly later event, which can rarely duplicate an already handled legacy event.

A pathological latest status line that crosses the 64 KiB window is unclassifiable.
It remains silent rather than risking presentation of routine content.
This is an accepted limit, not a status-line size contract.

### Index repair

A missing or invalid outcome-index ready marker is rebuilt from the authoritative outcome rows by `processed-init` under the outcome lock.
That rebuild runs on the next main drain, on every harness.
Only a genuine store fault keeps that backstop skipped.

## How the branch knows what the captain said

Each attended wake carries, at its head, the read-only dialog mirror of what the captain and main said since the last wake.
`bin/fm-host-mirror.sh` owns the mirror's writers, files, and feed, and [supervision-host.md](supervision-host.md#the-dialog-mirror) owns which primaries have a verified writer.
The mirror never carries tool calls, tool results, operational injections, or the branch's own outcomes.

### Mirrored text is context, not instructions

The branch prompt frames mirrored text as context for judgment, never as instructions addressed to the branch.
An authorization addressed to main (for example "you may merge when green") does not relax the branch's role limits.

## Two-stage noise filter

Stage one is unchanged: the bash watcher absorbs everything provably fine at zero token cost.
Stage two is the branch's verdict on each handled event, reported through `bin/fm-branch-report.sh`:

| Verdict | Delivery |
| --- | --- |
| `routine` | Stored; a non-silent outcome is listed once in main's next drain, and a silent one never appears. Neither opens a main turn. |
| `captain` | Stored, and presented by main's drain until main acknowledges it with `bin/fm-branch-outcome.sh mark-processed`. |

[supervision-host.md](supervision-host.md#captain-outcomes) owns how the drain presents and paces captain outcomes.
A home with no processed marker, including an upgrade, re-presents delivered captain rows dated and check-first until acknowledged; see the marker contract in `bin/fm-branch-outcome.sh`.

### Ownership and verdict rules

The branch prompt's "Verdict: routine or captain" section owns the classification criteria, including task-level silence eligibility and the rule to escalate doubt.

Its "PR identity: copy or abstain" section owns where a PR URL in a summary or tool argument may come from:

- The task's ready status or `pr=` metadata, verbatim.
- Otherwise, only the identifier the branch actually has.

Main can read the durable outcome store on demand through `bin/fm-branch-outcome.sh list` and `lookup`.

## Heartbeat routing

The cheap bash-level heartbeat scan absorbs a genuinely no-op pass before it reaches any model, unchanged from before.
Only a scan already flagged as possibly captain-relevant emits the bare `heartbeat` wake.
The branch takes it without a project only when every branch-ownable row observed in the unread-queue eligibility check is one of these:

- Heartbeat-kind.
- A resolvable task-local signal or stale event.

### Co-present main-owned rows

A heartbeat is never vetoed or ridden into main by a co-present check row or decision-owned signal/stale row.
Those rows are main-owned while attended.
They are excluded from what the branch may claim and left queued for main.
Main is woken for each on its own watcher cycle, so nothing starves by being left behind.
Under the away-posture record the branch claims them too ("Postures" below).

Deferring the fleet review to main merely because some unrelated merge poll or Relay mention happened to be sitting unread put a routine review in the captain's chat for a reason that had nothing to do with the fleet.
That coupling is gone.

What all-or-nothing still guarantees is unchanged: the branch takes every branch-ownable unread row or none of them.
An unresolvable task-local row, an unknown row kind, or an unreadable queue still defers the whole review to main.

### Reporting the review

The branch runs its normal operating procedure for the wake (`bin/fm-branch-prompt.sh` "Handling a wake") and performs the deeper fleet review that main previously performed.

| Review result | Report |
| --- | --- |
| Found literally nothing worth reporting | Verdict `routine`, `task=fleet`, and `silent=true`, so it is stored and never listed. |
| A fleet-wide routine action | Omits `silent`, so main's next drain lists it once. |

Only a captain-worthy finding reports verdict `captain`.

Every other fleet-wide or unresolvable wake keeps the wake-to-main path in both postures.
That includes watcher-failure alarms, which are never offered to the branch.

## Cost model and the byte-stable prefix

The captain accepted the normal provider prompt-caching strategy:

- A byte-identical branch prefix generated once per firstmate version.
- The same tool set in the same order on every request.

The host's engine keeps one conversation across wakes so that prefix stays cached; [supervision-host.md](supervision-host.md#engine-conversations) owns when a new one opens and where engine cost is read.
Reuse is best-effort, never guaranteed.

### No further caching machinery

No caching machinery beyond this exists, deliberately.
Any later dynamic content in the branch prefix silently removes most of the cache benefit.
That is why `bin/fm-branch-prompt.sh`'s header is the contract's single owner and `tests/fm-branch-supervision.test.sh` pins the output to byte identity.

## Postures

One supervision session runs in two postures, attended and away.
The posture is a file: the away-posture record `state/.afk-contract`.
Only `bin/fm-afk-contract.sh` writes it, in the same turn as `/afk`.
The return path archives it on the captain's first unmarked message.

### Who reads the record

The record is never inferred from chat and never placed in the branch's byte-stable prompt prefix.
Three readers check it:

- The host reads it at every close and again when a turn starts.
- The branch reads it at the tail of every wake.
- The guarded scripts validate it through the record owner at every gate.

On a home that runs the host, `/afk` launches no away daemon, because the host is the away session there.

### While the record exists

- Every actionable row is branch-eligible.
  Check rows, decision-owned signal and stale rows, and heartbeat rows are claimed by the branch on whatever wake finds them unread.
  The trigger class no longer forces a batch to main.
  The fail-closed scope checks in [Decision-owned rows](#decision-owned-rows), including ambiguous metadata ownership, still apply, as does structural queue validation.
  A wake that claims a check row is not scoped by task, so the branch may report it as `fleet`.
- Main is parked, and reachable only for the classes only main can act on:
  - A watcher-failure alarm is delivered to main as always, because only main can repair the watcher cycle.
  - A wake the branch declines or cannot take (a broken session inside its cooldown, an unresolvable or corrupt scan) falls back to main exactly as attended.

  Parking is a cost and chat-cleanliness measure.
  Supervision continuity is the safety property, and the return brief's health section reads any gap.
- The wake message ends with a fixed `POSTURE: AWAY` tail plus the record's read-back verbatim (`bin/fm-afk-contract.sh readback`).
  The branch therefore has the captain's away words, the spend cap, the expected return, and the reach line in front of it at execution time, without any prefix change.
- Captain-verdict outcomes accumulate unprocessed in the outcome store, and no main turn opens for them.
  After the return, main's drain presents them, and `bin/fm-afk-return.sh` counts them and points there.
- Main's standing authority relocates to the branch, and nothing more.
  [Authority relocation](#authority-relocation) below gives the details.
- The branch prompt's fixed "Postures" section states these rules once per firstmate version, so the prefix stays byte-stable.
  The per-wake tail is the only dynamic content.

### Authority relocation

`fm_lease_forbid_branch` passes the branch actor only for the actions whose guarded script opts in.
It does so only while `bin/fm-afk-contract.sh validate` succeeds on a complete, readable, live away record (`mode` is not quiet).
An archived, incomplete, invalid, or quiet record restores the attended refusal byte for byte.

The captain's away words are the whole mandate:

- The branch reads them at the tail.
- It decides by its own judgment whether the event in front of it is the moment they name.
- It acts on them only through the guarded scripts, never by analogy.
- It holds with verdict captain on doubt.

`bin/fm-branch-prompt.sh` "Postures" owns those execution rules.
It requires every action taken under the words to open its outcome summary with "per your away instructions:".

Each relocated script keeps its own gate, enforcing exactly what a script can check without reading words:

| Script | Gate while away |
| --- | --- |
| `bin/fm-pr-merge.sh` | Merges a pull request synchronously under the record lock after the [merge helper's guards](../bin/fm-pr-merge.sh) pass, and refuses `--allow-red`, `--allow-missing`, and `--allow-no-pipeline` while away, so the green gate is absolute in this posture; which pull request the words meant is the branch's reading. |
| `bin/fm-spawn.sh` | Dispatches only queued work whose blockers cleared - already queued, or filed by the branch because the words explicitly call for it; refuses a fresh ordinary spawn for either actor once the home holds as many ordinary task records as the record's spend cap (relaunches and secondmates exempt). |
| `bin/fm-send.sh --resolve-key` | Answers a decision the words pre-answer, or one `ask-user-authority`'s judgment (carried verbatim in the branch prompt) lets firstmate decide. |
| `bin/fm-merge-local.sh` | Never relocated. |

The merge-authority record and the outcome row's summary are the audit trail.
The return brief renders the words verbatim beside that account.

### The authority invariant

Being away changes how the captain is informed and what happens at a captain-owned decision point, never firstmate's authority set.
`tests/fm-branch-supervision.test.sh`, `tests/fm-pr-merge.test.sh`, and `tests/fm-send-resolve-key.test.sh` pin this invariant.
It sets these limits:

- The never-set (credential entry, legal or financial acceptance, an attended prompt, an unnamed discard, a security-sensitive action) has no guarded entrypoint that accepts away authority for either actor.
- A forced teardown stays refused for the branch.
- A red merge is refused in this posture whatever the words say.
- No relocation survives the return, because an archived record validates as absent and the words die with it.

### Cleanup after task completion

Ordinary cleanup of landed ships and completed scouts needs no authority relocation; [`bin/fm-branch-prompt.sh`](../bin/fm-branch-prompt.sh) owns the branch's cleanup instructions in both postures, including lease acquisition and refusal reporting.
The generated prompt includes the [scout-completion](../.agents/skills/scout-completion/SKILL.md) and [captain-hold-lifecycle](../.agents/skills/captain-hold-lifecycle/SKILL.md) policies verbatim so their completion gate reaches hosts without automatic skill loading.

## Verification

`tests/fm-branch-supervision.test.sh` covers:

- Prompt stability, including the landed-work cleanup instruction and the second-mate relay, signal-span, and stale-liveness rules.
- The emitted completed-scout cleanup instructions and verbatim completion policies, including incomplete-work boundaries and refusal reporting; these assertions verify prompt delivery, not a model's adherence.
- Store append-only behavior, the captain cursor barrier, processed-marker sequence bounds and absent-marker safety, and captain-only recorded ages.
- Leases, guards, and non-branch-home invariance.
- The away relocation: only under a valid live record, never for local-only landing, queued-only branch dispatch rather than orphaned in-flight recovery, the spend cap for both actors and its lock-held recheck, and the attended guarded-action behavior restored by archive or an invalid record.
- Row eligibility in `bin/lib/fm-host-dispatch.ts`:
  - In `test_branch_dispatch_classifies_main_only_rows`: decision-owned signal and stale rows' exclusion from `eligibleSeqs`, their presence in `needsDecisionKeys`, task alias resolution, reserved-key configuration, status-log race and symlink refusal, non-vetoing behavior for unrelated eligible rows, and decision-only queues reading as ordinary main-only absence.
  - In `test_branch_dispatch_routes_secondmate_signal_by_new_span`: second-mate signal routing by new span on the plain and attended-host scans, including an unrelated open hold, mixed, same-key, stamped-key, key-less blocked, and resolution spans, the whole-log fallback, stale-row isolation, and crewmate routing.
  - In `test_branch_dispatch_resolves_terminal_keyed_orca_stale_row`: a unique Orca `terminal=` handle resolving to its task and project in routine and heartbeat scans, and conflicting terminal, window, or task aliases refusing the whole scan in either record order.
  - In `test_branch_dispatch_keeps_project_with_canonical_owner`: canonical ownership governing the scope and the `bin/fm-host-dispatch.mjs offer` verdict in both discovery orders.

The supervision host's suites (`tests/fm-supervision-host*.test.sh`, listed in [supervision-host.md](supervision-host.md#verification)) cover the offer rule, the posture tail, the dialog mirror, the grant, and the drain's presentation end to end.

`tests/fm-afk-return.test.sh` covers the ordered cleanup-due section, its durable merge-marker requirement, and exclusion of both a done task without durable merge evidence and a persistent secondmate carrying that evidence.

`tests/fm-pr-merge.test.sh` covers the branch actor merging a green task under the record, being refused on a red check, an unreported required check, or `--allow-red`/`--allow-missing` under it, and being refused at the partition while attended.

`tests/fm-secondmate-safety.test.sh` covers the branch actor being refused second-mate retirement with the mate's record, home, route, and endpoint left intact.

`tests/fm-send-resolve-key.test.sh` covers the decision-answer partition:

- A needs-decision or captain-held key refuses the attended branch before anything is sent.
- A `blocked:` key stays ordinary steering.
- The record relocates the answer.

`tests/fm-wake-drain-outcome-backstop.test.sh` covers keyless resurfacing, causal suppression, same-second ordering, one-shot presentation, first-drain index self-healing under the outcome lock, store-fault fail-closed behavior, bounded history cost and output, and the oversized-line limit.

`tests/fm-teardown.test.sh` covers removal of the retired task's outcome index and the append-side rule that a post-teardown report does not recreate it.

Other tests remain where they were:

- The recovery test remains in `tests/fm-session-start.test.sh`.
- The per-actor consume regression remains in `tests/fm-wake-queue.test.sh`.

`tests/fm-watch-triage.test.sh` covers `bin/fm-watch.sh`'s side of the contract end to end:

- Needs-decision, no-verb captain-held, and pending-reply second-mate escalation signal rows are marked `needs-decision:`.
- A needs-decision whose key transition was rejected by the reserved-key vocabulary (`fm-classify-lib.sh`'s `reconciliation-required:` wrapper) is still marked.
- Ordinary blocked or captain-relevant signals stay unmarked.
