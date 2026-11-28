# WP-05A.2 — CR-01 Review-Fix Handoff

**Status:** READY FOR FREEBUFF — implementation requires the user's explicit authorization in chat  
**Parent work package:** WP-05A.2 — Anchor State Transitions  
**Review finding:** CR-01 (P1 — Blocking)  
**Review decision:** CHANGES REQUESTED  
**Primary review:** [CODE_REVIEW.md](CODE_REVIEW.md)  
**Approved behavior:** [SPEC.md](SPEC.md)  
**Required tests:** [TEST_PLAN.md](TEST_PLAN.md)

## 1. Objective

Resolve CR-01 only: when an Anchor is in `WAIT_ACTIVATION` and the Grid Engine observes the valid activation crossing, the resulting transition to `READY` must be persisted through the canonical Entry Mapping Reducer and Journal.

Today the Engine can change its in-memory Anchor state to `READY`, but the Reducer remains durably at `WAIT_ACTIVATION`. The Reducer consequently rejects the next Anchor Entry Intent and confirmed Position Mapping. Restart preserves the blocked state.

The fix must make the Engine's valid activation transition and the Reducer's durable state converge. Do not bypass or weaken the Reducer's existing Anchor READY checks.

## 2. Required behavior

Use the approved activation direction from SPEC §5.3:

- BUY Anchor: `WAIT_ACTIVATION` becomes `READY` only after an upward crossing through Anchor Price.
- SELL Anchor: `WAIT_ACTIVATION` becomes `READY` only after a downward crossing through Anchor Price.
- A non-qualifying movement leaves the Anchor in `WAIT_ACTIVATION`.
- The transition must be durably journaled and replayable before the Reducer accepts a new Anchor Entry Intent.

Implement a validated Anchor-state lifecycle transition. An `ANCHOR_STATE` event analogous to the existing `LEVEL_STATE` event is the expected approach, unless the current architecture provides an equally explicit and durable equivalent.

The transition contract must enforce:

1. The only newly required transition is Anchor `WAIT_ACTIVATION -> READY`.
2. The Anchor must have no Position Mapping when this transition is applied.
3. `ACTIVE` must continue to mean exactly one Anchor Position Mapping exists.
4. `READY` and `WAIT_ACTIVATION` must continue to mean no Anchor Position Mapping exists.
5. Reject unknown/invalid states, invalid transition origins, duplicate or conflicting state transitions, and any attempt to transition while an Anchor mapping exists. Follow the Reducer's existing fail-closed / Recovery Error policy.
6. Validate all preconditions before mutating state.
7. Append the durable record before applying the in-memory state, following the established Journal/Reducer contract. Append/flush failure must not report success or change canonical in-memory state.
8. Journal replay and Snapshot export/restore must preserve the resulting Anchor `READY` state. No new Snapshot field should be added if the existing Anchor State field already represents it.
9. The Engine, Runtime Coordinator and Reducer must not retain contradictory Anchor states after a successful activation crossing.

Keep the existing Anchor Entry Intent and Position Mapping READY guards intact. Do not treat Entry Request Accepted or Deal Association as Anchor activation evidence.

## 3. Implementation scope

### Allowed

- Add the smallest durable Reducer event/API needed for Anchor state transition.
- Wire the Engine activation-crossing result through the Runtime Coordinator to that durable API.
- Add Journal replay support for the new lifecycle event.
- Add or refine validation necessary to preserve the Anchor mapping/state invariants.
- Add focused no-trade tests and update the implementation report / WP documentation to describe the fix.

### Not allowed

- No WP-05C Open Positions reconciliation adapter, account scan, `PositionsTotal()`, or position snapshot acquisition.
- No WP-05D production `OnTradeTransaction` integration.
- No MT5 Deal History lookup or close-reason classification.
- No changes to Grid trading behavior, activation direction, entry selection, crossing rules, Bounds, lot sizing, or execution policy beyond the minimal state synchronization required.
- No new processed-event registry or unrelated persistence/schema redesign.
- No trade requests of any kind: no `OrderSend`, `CTrade`, `Buy()`, `Sell()`, `PositionClose()`, Demo or Live operation.
- No changes to unrelated staged implementation, formatting sweeps, refactors, or cleanup.
- No commit or push.

## 4. Required regression tests

Add focused tests to the existing relevant test suites. Use the existing test style and deterministic no-trade fakes.

| ID | Scenario | Expected |
|---|---|---|
| CR01-01 | Anchor Full Close commits `WAIT_ACTIVATION` | Reducer and Engine agree on `WAIT_ACTIVATION`; mapping is absent |
| CR01-02 | BUY Anchor receives valid upward activation crossing | Durable Anchor state becomes `READY` |
| CR01-03 | SELL Anchor receives valid downward activation crossing | Durable Anchor state becomes `READY` |
| CR01-04 | BUY movement is not an upward crossing | Remains `WAIT_ACTIVATION`; no READY event appended |
| CR01-05 | SELL movement is not a downward crossing | Remains `WAIT_ACTIVATION`; no READY event appended |
| CR01-06 | Replay the committed Anchor activation event | Reducer restores Anchor `READY` |
| CR01-07 | Snapshot after activation, then restore/restart | Anchor remains `READY`; no Anchor mapping exists |
| CR01-08 | After durable activation, submit Anchor Entry Intent | Intent is accepted under existing validation |
| CR01-09 | Confirm the subsequent Anchor Position Mapping | Mapping is stored and Anchor becomes `ACTIVE` |
| CR01-10 | Attempt Anchor state transition while an Anchor mapping exists | Reject / Recovery Error; mapping and `ACTIVE` state unchanged |
| CR01-11 | Attempt invalid origin, target or unsupported Anchor transition | Reject / Recovery Error; no partial mutation |
| CR01-12 | Journal append/flush failure for activation transition | No success; canonical in-memory state remains `WAIT_ACTIVATION` |
| CR01-13 | Restart after durable append but before in-memory apply (where supported by existing test doubles) | Replay converges to `READY` exactly once |

Also run the existing relevant reducer, engine, runtime-coordinator, persistence and restart-persistence suites. Do not expand this into unrelated test cleanup.

## 5. Required implementation report update

Update `IMPLEMENTATION_REPORT.md` with a clearly separated **CR-01 Review Fix** subsection:

- root cause;
- event/API and runtime flow added;
- validation/invariant behavior;
- exact files changed;
- tests added and exact results (Freebuff must not claim MetaEditor results);
- confirmation that no trade requests were sent;
- any deviation or limitation.

Do not rewrite or erase the original implementation history. Preserve the existing review artifact and record the fix as a response to CR-01.

## 6. Developer workflow and safety

1. Re-read the current Git status before editing. The original WP-05A.2 implementation is staged and must be preserved. The CTO review/documentation files may also be staged; do not assume a clean tree.
2. Work only on the current branch, `feature/grid-trading`.
3. Do not reset, checkout, clean, stash, unstage, overwrite, or revert existing staged/unstaged work.
4. Keep the fix limited to CR-01 and inspect the final diff against both the current working tree and the staged baseline.
5. Run static checks and `git diff --check` plus `git diff --cached --check` without changing unrelated staged content.
6. Stop after implementation and report the exact files, behavior, tests, and remaining user verification steps. Do not commit/push and do not begin another WP.

## 7. Completion and review gate

After Freebuff completes:

1. User runs MetaEditor Compile and the required no-trade Grid Regression tests, then reports exact results.
2. CTO reviews the CR-01 fix and the combined WP-05A.2 implementation against SPEC and TEST_PLAN.
3. If the finding is resolved and all gates pass, CTO may recommend APPROVED; WP-05A.2 is not Done until the established documentation gate and user confirmation are complete.
4. Do not start WP-05C until WP-05A.2 is formally closed and the user authorizes the next work package.

**This document is an implementation handoff only. It does not itself authorize Freebuff to edit source.**
