# WP-05A.2 — Anchor State Transitions Implementation Report

**Status: IMPLEMENTED — user-reported MetaEditor Compile/Test PASS 2026-11-23; awaiting CTO Code Review**
**Developer:** Freebuff
**Date:** 2026-11-23
**Specification:** [SPEC.md](SPEC.md)
**Test Plan:** [TEST_PLAN.md](TEST_PLAN.md)
**Task:** [IMPLEMENTATION_TASK.md](IMPLEMENTATION_TASK.md)

Freebuff did not run MetaEditor/MT5 compilation or runtime tests in its
implementation environment. The user subsequently reported MetaEditor Compile
PASS and Grid Regression Test PASS on 2026-11-23; see §8.

## 1. Files changed

| File | Change |
|---|---|
| `Include/BotTrade/Grid/GridTypes.mqh` | `WAIT_RETURN` documented as a reserved legacy numeric slot; added `TGKGridNormalizeLevelState()` for READY normalization. |
| `Include/BotTrade/Grid/GridLevelEngine.mqh` | Reason-free `StateAfterPositionClose()`; `RecordPositionClosed()` no longer takes a close reason; `SetLevelState()`/`SetAnchorState()` normalize legacy `WAIT_RETURN` to `READY`. |
| `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh` | Removed TP/NON_TP close-reason classification from close events; full close is keyed by the tracked logical mapping only. |
| `Include/BotTrade/Grid/GridEntryExecutionPolicy.mqh` | Eligibility uses the normalized state; `WAIT_RETURN` is treated as `READY`. |
| `Include/BotTrade/Grid/GridPersistence.mqh` | `SaveLevelState()`/`RestoreLevelState()` normalize legacy `WAIT_RETURN` to `READY`. |
| `Include/BotTrade/Grid/GridEntryMappingReducer.mqh` | Anchor activation on confirmed mapping; one-record Partial Close metadata; reason-free atomic Full Close; legacy close replay; Anchor State in Snapshot export/restore; strict preconditions before mutation. |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` | Updated legacy expectations and added WP-05A.2 coverage (activation, partial close, full close, legacy replay, idempotency, snapshot). |
| `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5` | Reason-free close tests; equality/wrong-side coverage; legacy `WAIT_RETURN` normalization assertions. |
| `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` | Removed close-reason fixtures; updated next-state expectations; invalid-mapping close event replaces unknown-reason coverage. |
| `Experts/TGK/Tests/Grids/test_grid_persistence.mq5` | Legacy `WAIT_RETURN` save/restore now expects `READY`. |
| `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5` | Legacy `WAIT_RETURN` level restores as `READY`. |

No production EA, persistence authority, bounds, lot sizing, entry selection or
crossing behavior was changed. No Closing Deal History, `PositionsTotal()` scan,
or `OnTradeTransaction` integration was added.

## 2. Design decisions

1. **One state vocabulary.** `TGKGridNormalizeLevelState()` is the single
   normalization point: `WAIT_RETURN` → `READY`, every other value unchanged.
   The enum slot value `2` is reserved and `WAIT_ACTIVATION` keeps value `3`.
2. **Anchor activation is mapping-driven.** `ApplyPositionMapping()` sets
   `m_anchor_state = ACTIVE` in the same replay event that stores the mapping.
   Entry Intent, Execution Result and Deal Association alone never activate it.
   Anchor Entry Intent/Mapping now require Anchor State `READY`.
3. **Partial Close is one metadata record.** New lifecycle payload
   `v1|POSITION_METADATA|<position_identifier>|<volume>|<position_ticket>` keeps
   Ticket and Volume from one observation, preserves the mapping and `ACTIVE`,
   rejects volume growth, zero volume, an unknown Identifier and a no-change
   duplicate. Legacy `POSITION_VOLUME` / `POSITION_TICKET` remain replayable.
4. **Full Close is reason-free.** New payload
   `v1|POSITION_CLOSED|<position_identifier>|<next_state>` (four fields) with
   no TP/NON_TP, close price or close Deal. The logical target, Level index, Request ID
   and ticket come from the mapped Position. Legacy five-field payloads
   (`TP|state`, `NON_TP|state`, `NONE` for Anchor) are still accepted on replay;
   their reason is ignored and `WAIT_RETURN`/Anchor `NONE` normalize to `READY`.
5. **Atomic apply order.** Preconditions (mapping exists, state token valid,
   next state not `ACTIVE`, Level state row exists) are validated first. The
   Level/Anchor state is written before the mapping, Deals and Request are
   removed, so a rejected record cannot leave a partially applied transition.
6. **Anchor State is durable in the V1 Snapshot.** The `STATE` header gains one
   trailing integer field after `level_state_count`; the official reducer
   Snapshot now has 18 header fields. Restore validates the Anchor State,
   normalizes numeric `2` to `READY`, and requires `ACTIVE` exactly when an
   Anchor mapping exists. A Snapshot without the Anchor State field fails closed.
7. **State-based idempotency.** No processed-close registry exists. A close
   record with no matching mapping is rejected; after a durable close the
   mapping is gone, so a duplicate snapshot produces no second transition.

## 3. Acceptance criteria mapping

| SPEC criterion | Implementation | Tests |
|---|---|---|
| Anchor mapping confirmation sets Anchor ACTIVE | `ApplyPositionMapping()` ANCHOR branch | A04 |
| Normal Level confirmation keeps Level ACTIVE | unchanged LEVEL branch | Existing reducer mapping test |
| Partial close updates Volume/Ticket, stays ACTIVE | `ApplyPositionMetadata()` | P01, P04, P05 |
| Full close removes mapping and updates state in one record | `ApplyPositionClosed()` | C11, C12 |
| TP/SL/manual produce identical transitions | reason-free engine and reducer payload | C07–C10 equivalent (engine reason-free block + legacy L01–L04) |
| BUY/SELL wrong-side and activation rules unchanged | `StateAfterPositionClose()`, `IsWrongSideAfterEntryMove()` | C01–C06, R01–R05 |
| `WAIT_RETURN` never written; normalized on load | normalization helper + setters + Snapshot restore | R06–R08, L01–L06 |
| Duplicate snapshots append no duplicate close | mapping presence check | I01, I06 |
| Restart/replay converges at each crash boundary | replay-only transitions | I02, I03, I07, F04, F08 |
| Old close cannot mutate a new Position at the same Level | Identifier lookup | I07, I08 |
| Invalid/conflicting evidence fails closed without partial mutation | precondition-before-mutation | C13–C15, P06–P08, A05, A06, F01, F05 |
| No Deal History close lookup | no history API added | static inspection |
| No test sends a trade request | tests use records/fakes only | static inspection |

## 4. TEST_PLAN coverage and results

Implemented in `test_grid_entry_mapping_reducer.mq5`, `test_grid_level_engine.mq5`
and `test_grid_level_runtime_coordinator.mq5`:

- **A01–A06:** Anchor activation evidence, duplicate and invalid identity.
- **P01, P02, P04–P09:** Partial Close, Ticket refresh, one metadata record,
  zero/unknown/growing/unchanged evidence. Existing reducer test covers Level
  partial close (P02).
- **C01–C06:** Engine quote-side and equality rules.
- **C11–C15:** Anchor/Level atomic close, unknown Identifier, invalid next state.
  C07–C10 are represented by the reason-free engine contract and legacy replay
  tests: no reason branch exists.
- **R01–R08:** Activation/equality, READY/legacy eligibility and normalization.
- **I01–I07, I09:** State-based idempotency, duplicate close, remapped Level.
  I08 is enforced structurally: the close payload has no Ticket field and lookup
  is by Identifier only.
- **L01–L07:** Legacy TP/NON_TP/`NONE` close replay, numeric normalization,
  `WAIT_ACTIVATION` ordinal, missing Anchor State rejection.
- **F01, F04–F08:** Replay-after-append convergence, Snapshot after close,
  Snapshot + later Journal replay. F02/F03 storage failure behavior is covered
  by the existing `test_grid_entry_mapping_storage` / `test_grid_entry_execution`
  fake-port suites; F06 by the existing capacity tests.
- **Existing suites:** all reducer/snapshot/policy/execution fixtures were
  reviewed against the new signatures; no other test EA calls
  `RecordPositionClosed()` or sets a close reason.

**Exact results:** not executed by Freebuff. No MetaEditor/MT5 compiler is
available in this environment. The user must report Compile and Run results.
Static checks performed: parenthesis/bracket/brace balance on all changed MQL5
files, `git diff --check` (clean), and a scan confirming no `CTrade`,
`OrderSend`, `PositionClose` or close-reason usage remains in the changed test
paths.

## 5. Compatibility behavior

- Existing V1 entry records (`ENTRY_INTENT`, `EXECUTION_RESULT`,
  `DEAL_ASSOCIATION`, `POSITION_MAPPING`) replay unchanged.
- Legacy `POSITION_VOLUME`, `POSITION_TICKET`, `LEVEL_STATE` and `RESET_COMMITTED`
  replay unchanged.
- Legacy `POSITION_CLOSED` records with `TP`/`NON_TP` and a next state are
  accepted; the reason is ignored and legacy `WAIT_RETURN` becomes `READY`.
- Legacy Anchor close records with `NONE` normalize to `READY`; legacy Anchor
  close records with an explicit `READY`/`WAIT_ACTIVATION` state are accepted.
- Snapshot wire shape changed by one required trailing Anchor State field.
  A Snapshot written before this change (17 header fields) is rejected and the
  reducer enters `RECOVERY_ERROR`, as specified. Legacy numeric level/Anchor
  state `2` is normalized to `READY`.
- `GridPersistence` Global-Variable level states normalize `WAIT_RETURN` to
  `READY` on save and restore.

## 6. Known limitations and deviations

- No MT5 Open Positions adapter, completeness/stable-snapshot verification or
  production `OnTradeTransaction` integration was added (WP-05C / WP-05D).
- The Snapshot layout change is deliberately incompatible with pre-WP-05A.2
  snapshots; no migration was requested or implemented.
- The caller that will emit `POSITION_METADATA` and the new reason-free
  `POSITION_CLOSED` payload is the future reconciliation layer. This work
  package implements and tests the durable reducer contract only.
- No deviation from the approved SPEC/Payload contract was required.

## 7. Safety statement

No trade request was sent. No test uses `CTrade`, `OrderSend`, `PositionClose`
or any Demo/Live trading API. No commit, push, reset, checkout, clean or stash
was performed. Pre-existing working-tree changes were preserved.

## 8. User verification (user-reported 2026-11-23)

The user reported that every changed file compiled PASS in MetaEditor and that
the tests passed after the fix below.

First full test run reported 3 failing assertions in
`test_grid_entry_mapping_reducer`:

```
FAIL: replay only the first committed close record | actual=false
FAIL: C16 first close removes one mapping | expected=1, actual=0
FAIL: C16 second Level remains ACTIVE until its record | expected=1, actual=-1
```

Cause was a test-fixture defect, not reducer behavior: `Replay()` rejects any
`record_count` that differs from `ArraySize(records)`. The C16 interrupted-replay
case passed `first_close_count + 1` together with the full 12-record array, so
Replay returned false before applying any record, leaving no Position and no
Level State. The case now copies the record prefix into
`interrupted_close_records` and replays that array with
`ArraySize(interrupted_close_records)`. No reducer or other production source
changed for this fix.

## 9. Next step

Formal CTO Code Review against SPEC.md, TEST_PLAN.md and this report. Trello is
in `Code Review`; `Done` still requires an APPROVED review, documentation gate
and user confirmation.
