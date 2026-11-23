# WP-05A.2 — CTO Code Review

**Review date:** 2026-11-23  
**Review outcome:** CHANGES REQUESTED  
**Reviewed against:** `SPEC.md`, `TEST_PLAN.md`, `IMPLEMENTATION_TASK.md`, `IMPLEMENTATION_REPORT.md`  
**User verification:** MetaEditor Compile PASS and Grid no-trade Test PASS, user-reported 2026-11-23

## 1. Scope reviewed

Reviewed the complete staged WP-05A.2 diff across the Reducer, Engine, Runtime Coordinator, Execution Policy, persistence normalization, affected tests, and project documentation.

Repository state at review:
- Branch: `feature/grid-trading`
- Freebuff changes are staged but not committed.
- No unstaged changes were present at review time.
- `git diff --cached --check`: PASS.
- Scan of changed Grid test files found no `CTrade`, `OrderSend`, `PositionClose`, `Buy()` or `Sell()` calls.
- No source files were changed by the CTO review.

## 2. Findings

### CR-01 — Anchor WAIT_ACTIVATION has no durable transition back to READY

**Severity:** P1 — Blocking  
**Files / locations:**
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh:656-661` — Anchor Entry Intent is accepted only while the Reducer's Anchor State is READY.
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh:825-828` — Anchor Position Mapping confirmation is also restricted to READY.
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh:1025-1044` — Full Close can persist Anchor State as WAIT_ACTIVATION.
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh:896-919` — the only state-transition lifecycle handler is `LEVEL_STATE`, and it updates normal Levels only.
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh:1126-1145` — `ApplyLifecycleUpdate()` has no Anchor State update event.
- `Include/BotTrade/Grid/GridLevelEngine.mqh:208-213` — the Engine can independently move its Anchor from WAIT_ACTIVATION to READY after the activation crossing.

**Problem:**

When an Anchor Full Close is recorded with next state WAIT_ACTIVATION, the Reducer stores that state. The Engine has logic to transition its own Anchor State back to READY after the required BUY/SELL activation crossing, but there is no corresponding durable Reducer event/API to record that transition. Unlike normal Levels, which have the `LEVEL_STATE` lifecycle record, the Anchor has no `ANCHOR_STATE` equivalent.

This creates a permanent gate: the Reducer rejects the next Anchor Entry Intent and Position Mapping while its state remains WAIT_ACTIVATION. A restart restores the same blocked state. The Engine becoming READY does not repair the Reducer's canonical durable state.

**Required resolution:**

Add a validated, durable Anchor-state transition contract (or another explicitly approved mechanism) that allows WAIT_ACTIVATION -> READY after the Engine's activation crossing, while preserving the invariants:
- ACTIVE requires exactly one Anchor Position Mapping.
- READY / WAIT_ACTIVATION require no Anchor Position Mapping.
- The transition must be journaled and replayable.
- Invalid transitions must fail closed.
- The Anchor state and normal Level state semantics must remain consistent.

Add tests covering at least:
1. Anchor Full Close -> WAIT_ACTIVATION.
2. Valid activation crossing -> durable Anchor READY.
3. Snapshot/restart preserves the resulting READY state.
4. A subsequent Anchor Entry Intent and confirmed Mapping can proceed.
5. Invalid activation/state transition while an Anchor mapping exists is rejected without mutation.

This finding is within the approved Anchor State Transition purpose; do not work around it by bypassing the Reducer's Anchor READY checks.

## 3. Documentation consistency

The implementation report has a stale sentence near its top:

> “No MetaEditor/MT5 compilation or runtime result is claimed in this report. The user must compile and run the tests before CTO Code Review begins.”

That conflicts with the report header and §8, which correctly record the user's Compile/Test PASS. Update this sentence to state that Freebuff did not run MetaEditor, and that the user subsequently reported Compile/Test PASS.

Also update the implementation handoff's execution status: `IMPLEMENTATION_TASK.md` still says not to start until the pre-change baseline is reported, although that gate was subsequently passed and implementation is complete. This is documentation cleanup, not a source blocker.

## 4. Positive review observations

- Position Identifier is used as the Full Close lookup identity; Position Ticket is updated as metadata.
- New Full Close payload is reason-free; legacy TP/NON_TP payloads are retained for replay and WAIT_RETURN is normalized to READY.
- Partial-close metadata carries Volume and Ticket together and rejects unknown identifiers, zero Volume, volume growth, and conflicting Ticket ownership.
- Full Close validates the mapped identifier and next state before changing the target state and removing the mapping.
- Snapshot now persists Anchor State and validates the ACTIVE/mapping invariant.
- No Closing Deal History lookup, live account scan, production OnTradeTransaction adapter, or trade request was introduced in the reviewed diff.
- The user-reported MetaEditor Compile/Test PASS is accepted as verification evidence; it does not override the P1 design gap above.

## 5. Decision

**CHANGES REQUESTED — do not mark WP-05A.2 Done and do not proceed to WP-05C.**

The staged implementation is preserved as-is. No commit, push, source edit, reset, checkout, clean, stash, or destructive operation was performed during this review.

A separate, explicit implementation handoff is required before Freebuff makes review fixes.