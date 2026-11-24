# WP-05A.2 — Anchor State Transitions Implementation Report

**Status: CR-01 REVIEW FIX IMPLEMENTED 2026-11-23 — user Compile/Test re-verification PASS reported 2026-11-24 — awaiting CTO re-review**
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

**Exact results:** Freebuff did not run MetaEditor/MT5; no compiler is available
in this environment. The user reported Compile PASS and Test PASS on 2026-11-23
for the pre-CR-01 implementation (see §8). The CR-01 fix changed source and
tests; after the compile and fixture corrections in §10.6/§10.6.1 the user
re-ran MetaEditor Compile and the full Grid test set and reported every test
file PASS on 2026-11-24. This report claims no independent compile or run
result.
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

Formal CTO Code Review against SPEC.md, TEST_PLAN.md and this report. The user
reported Compile and full-test PASS on 2026-11-24 after the corrections in
§10.6 and §10.6.1. Trello is in `Code Review`; `Done` still requires an
APPROVED review, documentation gate and user confirmation.

## 10. CR-01 Review Fix (2026-11-23)

Response to CR-01 in [CODE_REVIEW.md](CODE_REVIEW.md) and the handoff in
[CR-01_REVIEW_FIX_HANDOFF.md](CR-01_REVIEW_FIX_HANDOFF.md). The original
implementation history above is preserved unchanged.

### 10.1 Root cause

The Engine moved its own Anchor from `WAIT_ACTIVATION` to `READY` after the
activation crossing, but the durable Entry Mapping Reducer had no equivalent
lifecycle event. `LEVEL_STATE` exists only for normal Levels, so the Reducer
stayed at `WAIT_ACTIVATION`, kept rejecting the next Anchor Entry Intent and
Position Mapping, and a restart restored the same blocked state.

### 10.2 Event, API and runtime flow

- **Reducer:** new `ANCHOR_STATE` lifecycle payload
  `v1|ANCHOR_STATE|<config_epoch>|<state>`, applied by `ApplyAnchorState()`.
- **Engine:** `HasPendingAnchorActivation()` reports the observed
  `WAIT_ACTIVATION -> READY` crossing; `ConfirmAnchorActivation()` clears the
  report only after the durable record is committed. Entry confirmation/failure
  and a new close also clear any stale report.
- **Runtime Coordinator:** records the Engine's pending activation,
  `HasPendingAnchorActivation()`, `ConfirmAnchorActivation()`, and withholds or
  defers an Anchor entry candidate until the transition is durable.
- **Adapter:** `RecordAnchorActivation()` builds the payload and uses the
  existing `NextSequence` / `AppendRecord` / `Replay` contract, then confirms the
  Coordinator. The Journal append happens before the in-memory apply.

### 10.3 Validation and invariants

`ApplyAnchorState()` rejects an unknown payload shape, a non-token state, a
state other than `READY`, an invalid or mismatched Config Epoch, an origin other
than `WAIT_ACTIVATION` (so duplicate or conflicting transitions fail), and any
transition attempted while an Anchor Position Mapping exists. All preconditions
are checked before `m_anchor_state` changes; rejects follow the existing
`RECOVERY_ERROR` policy. `ACTIVE` still means exactly one Anchor mapping, and
`READY` / `WAIT_ACTIVATION` still mean none. The existing Anchor Entry Intent and
Position Mapping `READY` guards were not weakened. Entry Request Accepted and
Deal Association are not activation evidence.

### 10.4 Files changed by this fix

| File | Change |
|---|---|
| `Include/BotTrade/Grid/GridEntryMappingReducer.mqh` | `ApplyAnchorState()` validation plus `ANCHOR_STATE` dispatch. |
| `Include/BotTrade/Grid/GridLevelEngine.mqh` | Pending activation report and durable confirmation. |
| `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh` | Pending-activation tracking, entry gating/deferral and confirmation. |
| `Include/BotTrade/Grid/GridEntryExecutionAdapter.mqh` | `RecordAnchorActivation()` durable append + apply + confirm. |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` | CR01-01, 06, 07, 08, 09, 10, 11, 13. |
| `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5` | CR01-02, 03, 04, 05. |
| `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` | Activation gating, deferral and confirmation. |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5` | CR01-02 persistence success and CR01-12 append failure. |

### 10.5 Tests added and results

| ID | Case | Where |
|---|---|---|
| CR01-01 | Anchor Full Close commits `WAIT_ACTIVATION`, no mapping | reducer, engine, coordinator |
| CR01-02 | BUY upward crossing becomes durable `READY` | engine, adapter |
| CR01-03 | SELL downward crossing becomes durable `READY` | engine |
| CR01-04 | BUY non-qualifying movement keeps `WAIT_ACTIVATION` | engine |
| CR01-05 | SELL non-qualifying movement keeps `WAIT_ACTIVATION` | engine |
| CR01-06 | Replay restores Anchor `READY` | reducer |
| CR01-07 | Snapshot restore keeps `READY`, no Anchor mapping | reducer |
| CR01-08 | Anchor Entry Intent accepted after activation | reducer |
| CR01-09 | Anchor Position Mapping stored, Anchor `ACTIVE` | reducer |
| CR01-10 | Transition rejected while an Anchor mapping exists | reducer |
| CR01-11 | Invalid origin/target/state/epoch and duplicate rejected | reducer |
| CR01-12 | Append failure leaves canonical `WAIT_ACTIVATION` | adapter |
| CR01-13 | Replay after durable append converges to `READY` once | reducer |

**Results:** not executed by Freebuff (no MetaEditor/MT5 here). Static checks
only: brace/paren/bracket balance on the changed MQL5 files and
`git diff --check`. The user must report exact Compile and Test results (done:
the 2026-11-24 report of all-files PASS, see §10.6.1).

### 10.6 Compile fix after user report (2026-11-24)

ผู้ใช้รายงานผล Compile หลังแก้ CR-01 ว่ามี 2 ไฟล์ทดสอบไม่ผ่าน:

| File | Reported error | Location |
|---|---|---|
| `Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5` | `wrong parameters count, 6 passed, but 4 requires` | บรรทัด 187 |
| `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` | `wrong parameters count, 6 passed, but 4 requires` | บรรทัด 1088, 1105, 1128 |

**Root cause:** test เรียก `CTGKGridLevelRuntimeCoordinator::UpdatePrice()` ด้วย signature ของ Engine
(`previous_bid, previous_ask, current_bid, current_ask, ...`) ทั้งที่ Coordinator รับ
`current_bid, current_ask, result, candidate` และติดตาม previous quote ภายในเอง
(`m_previous_bid`/`m_previous_ask` ถูกตั้งจาก `Initialize()` และ `Reconcile()`)

**Fix:**

- เปลี่ยนทุกจุดที่ผิดให้เป็น 4 พารามิเตอร์ และสร้าง upward crossing จริงสำหรับ BUY
  (Ask 4000 → 3999 ก่อน แล้ว 3999 → 4000) แทนการส่ง previous/current ที่ไม่ขยับ
- `test_grid_level_runtime_coordinator.mq5`: การเคลื่อนลงใช้ 3999/3998 (3998.0/3999.0)
  สำหรับกรณีที่ต้องรอ confirmation (ดู §10.6.1 สำหรับการแก้ fixture รอบถัดไป)
- `test_grid_entry_execution.mq5`: fixture ของ CR01-02/CR01-12 เปลี่ยนจาก configuration
  เดี่ยว ๆ เป็น `AddAnchorActivationRecords()` (committed config → ANCHOR Entry Intent →
  Execution Result → Deal Association → Position Mapping → `POSITION_CLOSED|WAIT_ACTIVATION`)
  เพื่อให้ canonical Anchor State เป็น `WAIT_ACTIVATION` จริงตาม preconditions ของ
  `ApplyAnchorState()` และ Position Mapping ว่าง
- ตั้ง `port.next_sequence = reducer.LastSequence() + 1` ตามที่ `RecordAnchorActivation()`
  กำหนด (`port.NextSequence()` ต้องเท่ากับ `reducer.LastSequence() + 1`)

**Results:** แก้แล้ว, ตรวจ brace/paren/bracket balance ผ่านทั้ง 2 ไฟล์ และ
`git diff --check` clean. ผู้ใช้ Compile ผ่านหลังแก้ แต่การรัน test พบ assertion fail
ใน `test_grid_level_runtime_coordinator` — แก้ต่อใน §10.6.1

#### 10.6.1 Coordinator fixture correction after the test run (2026-11-24)

หลังแก้ compile error ผู้ใช้รัน test ทุกไฟล์: ผ่านทั้งหมด ยกเว้น
`test_grid_level_runtime_coordinator` ที่ fail 3 assertions ใน block
“Anchor activation is withheld until its durable confirmation”:

- `deferred Anchor candidate is offered after confirmation | expected=2, actual=1`
- `offered candidate is the Anchor | actual=false`
- `offered Anchor price | expected=4000.0, actual=0.0`

**Root cause (test fixture only, ไม่ใช่ production code):** fixture สร้าง downward move
เป็น 4000 → 3999 (Ask) แต่ `IsCrossedForEntry()` ของ BUY ต้องมี previous > level และ
current <= level ดังนั้น 4000 → 3999 ไม่ cross Anchor 4000 (ค่าหยุดที่ equality) —
จึงไม่เคยมี Anchor candidate ถูก defer เลย. หลัง `ConfirmAnchorActivation()` การเรียก
3999 → 4000 เป็นทิศทาง activation ไม่ใช่ทิศทาง entry จึงคืน `NO_CANDIDATE`

**Fix:** เพิ่ม upward move ไปที่ Ask 4002 ก่อน แล้วสร้าง downward crossing จริง
4002 → 4000 ขณะ pending (assert ว่าไม่ได้ offer และ `candidate.is_anchor == false`)
หลัง confirmation การเรียกที่ราคาเดิม 3999/4000 จะคืน deferred Anchor candidate
(`CANDIDATE_READY`, price 4000) ตามที่คาดไว้

**Results (user-reported 2026-11-24):** หลังแก้ fixture นี้ ผู้ใช้ Compile และรัน test
ทั้งชุดใหม่แล้วรายงานว่าผ่านครบทุกไฟล์. หลักฐาน Compile/Run มาจากผู้ใช้; Freebuff
ตรวจได้เฉพาะ static checks (brace/paren/bracket balance ผ่าน และ `git diff --check` clean)

### 10.7 Safety and limitations

No trade request was sent; no `CTrade`, `OrderSend`, `PositionClose`, account
scan, Deal History lookup, `OnTradeTransaction` integration, entry-selection,
Bounds or lot-sizing change was added. No new Snapshot field was introduced; the
existing Anchor State field carries the resulting `READY`. Limitation: the
runtime caller that performs the append is the future reconciliation/execution
integration (WP-05C/WP-05D); this work package implements and tests the durable
contract, the Engine signal, the Coordinator gate and the adapter API.
