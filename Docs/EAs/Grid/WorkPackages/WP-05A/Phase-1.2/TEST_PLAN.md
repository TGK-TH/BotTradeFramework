# WP-05A.2 — Anchor State Transitions Test Plan

**Status: APPROVED — Product Owner approval received 2026-11-23**
**Implementation gate: Source changes remain blocked until the user reports the pre-change Grid Regression Baseline.**
**Related:** [SPEC.md](SPEC.md)

## 1. Test Safety

- All tests are deterministic no-trade unit tests.
- No test may call OrderSend, CTrade Buy/Sell, PositionClose or any trade-request API.
- No Demo or Live integration test is included in this work package.
- Existing Demo Trade Request tests remain separately gated and are not part of this baseline.

## 2. Test Layers

1. Grid Level Engine state-transition tests.
2. Entry Mapping Reducer event-validation and state-transition tests.
3. Snapshot export/import and Journal replay tests.
4. Append/apply failure-boundary tests using the existing storage port/test doubles.
5. Regression tests for execution eligibility, mapping uniqueness and existing entry pipeline behavior.

## 3. Anchor Activation

| ID | Scenario | Expected |
|---|---|---|
| A01 | Anchor Entry Intent appended only | Anchor is not ACTIVE |
| A02 | Execution Result Accepted, no Position Mapping | Anchor is not ACTIVE |
| A03 | Deal Association exists, no Position Mapping | Anchor is not ACTIVE |
| A04 | Valid Anchor Position Mapping confirmed | Anchor State becomes ACTIVE |
| A05 | Duplicate/second Anchor mapping for same Instance | Reject; Recovery Error; no second mapping |
| A06 | Invalid Anchor mapping identity / config epoch | Reject; no Anchor State mutation |

## 4. Partial Close

| ID | Scenario | Expected |
|---|---|---|
| P01 | Anchor Volume decreases but remains positive | Mapping remains; Anchor ACTIVE |
| P02 | Normal Level Volume decreases but remains positive | Mapping remains; Level ACTIVE |
| P03 | Volume unchanged; Ticket unchanged | No durable event required |
| P04 | Ticket changes; Identifier remains the same | Refresh Ticket; retain mapping and ACTIVE |
| P05 | Volume and Ticket change in one observation | One metadata reconciliation record; ACTIVE |
| P06 | Volume becomes zero in a partial-close record | Reject; Full Close must use the Full Close transition |
| P07 | Volume increases for the same Hedging Position | Reject conflicting evidence; Recovery Required |
| P08 | Partial-close record references unknown Identifier | Reject; no state mutation |

## 5. Full Close and State Rules

Run every applicable scenario for both Anchor and a normal Level.

| ID | Mode | Current executable quote | Expected next state |
|---|---|---:|---|
| C01 | BUY | Level >= Ask | WAIT_ACTIVATION |
| C02 | BUY | Level < Ask | READY |
| C03 | SELL | Level <= Bid | WAIT_ACTIVATION |
| C04 | SELL | Level > Bid | READY |
| C05 | BUY | Level == Ask | WAIT_ACTIVATION |
| C06 | SELL | Level == Bid | WAIT_ACTIVATION |
| C07 | BUY | Any valid quote; prior close reason TP | Same result as reason-free rule |
| C08 | BUY | Same quote; prior close reason SL | Same result as reason-free rule |
| C09 | BUY | Same quote; prior close reason Manual | Same result as reason-free rule |
| C10 | SELL | Same quote; TP / SL / Manual | Same result for all reasons |
| C11 | Full close of Anchor | Anchor mapping removed and Anchor State updated atomically |
| C12 | Full close of normal Level | Level mapping removed and Level State updated atomically |
| C13 | Full close references unknown Identifier | Reject; Recovery Error |
| C14 | Full close Identifier maps to a different logical target than supplied evidence | Reject; no mutation |
| C15 | Full close event has ACTIVE as next state | Reject |
| C16 | Two mapped Positions close in one snapshot | Each receives its own ordered atomic transition; replay converges if interrupted between records |

## 6. Activation and Re-entry Regression

| ID | Scenario | Expected |
|---|---|---|
| R01 | BUY WAIT_ACTIVATION crossed upward through Level | READY |
| R02 | SELL WAIT_ACTIVATION crossed downward through Level | READY |
| R03 | BUY WAIT_ACTIVATION crossed downward | Remains WAIT_ACTIVATION |
| R04 | SELL WAIT_ACTIVATION crossed upward | Remains WAIT_ACTIVATION |
| R05 | READY candidate reaches existing entry crossing | Candidate remains eligible |
| R06 | WAIT_RETURN legacy value loaded | Normalized to READY |
| R07 | New Journal/Snapshot write after normalization | Writes READY; never WAIT_RETURN |
| R08 | READY and legacy WAIT_RETURN have same entry-policy outcome | Both eligible after normalization |

## 7. Idempotency and Restart

| ID | Scenario | Expected |
|---|---|---|
| I01 | Same complete snapshot processed twice after Full Close | Second pass emits no close event |
| I02 | Crash before close Journal append | Replay retains mapping; next fresh snapshot can close it |
| I03 | Crash after durable append but before reducer apply | Replay applies close exactly once |
| I04 | Restart after close commit | Mapping remains absent; state remains READY / WAIT_ACTIVATION |
| I05 | Replay committed close record from Journal | Same canonical state as before restart |
| I06 | Duplicate close record appended with a new sequence after mapping removed | Reject; no state mutation |
| I07 | Same logical Level later maps a new Position Identifier; old close record reappears | Reject; new mapping and ACTIVE state remain unchanged |
| I08 | Old close record has same Identifier but stale Ticket | Identifier is authoritative; ticket mismatch must not redirect close to another mapping |
| I09 | Duplicate metadata observation with unchanged Volume/Ticket | No additional record |
| I10 | Position Identifier is reused or conflicts with another mapping | Reject; Recovery Required |

## 8. Atomicity and Failure Injection

| ID | Failure point | Expected |
|---|---|---|
| F01 | Invalid payload before mutation | Reducer unchanged |
| F02 | Journal Append fails | No in-memory transition; caller reports failure |
| F03 | Flush/commit fails | No success; previous durable generation remains authoritative |
| F04 | Crash immediately after durable append | Replay completes the transition |
| F05 | Reducer validation fails after append | Recovery Required; replay/validation required before trading |
| F06 | Array capacity / allocation failure during application | No partially mutated reducer state |
| F07 | Snapshot export after close | Position absent and matching Anchor/Level state present in same snapshot generation |
| F08 | Snapshot import then replay later Journal records | Same canonical state as uninterrupted replay |

## 9. Legacy Replay and Persistence

| ID | Scenario | Expected |
|---|---|---|
| L01 | Replay old V1 TP + WAIT_RETURN close record | Mapping removed; resulting state READY |
| L02 | Replay old V1 NON_TP + READY close record | Mapping removed; resulting state READY |
| L03 | Replay old V1 NON_TP + WAIT_ACTIVATION close record | Mapping removed; resulting state WAIT_ACTIVATION |
| L04 | Replay old Anchor close record with NONE state | Mapping removed; Anchor normalized to READY |
| L05 | Load legacy numeric WAIT_RETURN state | Normalize to READY |
| L06 | Load existing WAIT_ACTIVATION numeric value | Remains WAIT_ACTIVATION; numeric ordinal preserved |
| L07 | Load snapshot missing required Anchor State | Fail Closed / Recovery Required |
| L08 | Replay valid existing entry pipeline records | Existing Position Mapping and request resolution behavior preserved |

## 10. Regression Gate

The implementation must also pass the full current no-trade Grid Regression suite, including:

- `test_grid_position_reconciler`
- `test_grid_lifecycle`
- `test_grid_state_machine`
- `test_grid_types`
- `test_grid_persistence`
- `test_grid_identity`
- `test_grid_identity_multichart`
- `test_grid_restart_persistence`
- `test_grid_level_engine`
- `test_grid_level_runtime_coordinator`
- `test_grid_entry_mapping_reducer`
- `test_grid_entry_mapping_storage`
- `test_grid_entry_mapping_snapshot`
- `test_grid_entry_execution_policy`
- `test_grid_entry_execution_resolver`
- `test_grid_entry_execution_pipeline`
- `test_grid_entry_execution`
- `test_grid_runtime_orchestrator`

The exact current regression inventory must be rechecked immediately before implementation; this list is not a substitute for the user's pre-change baseline report.

## 11. Exit Criteria

- All WP-05A.2 tests pass in MetaEditor as reported by the user.
- Full no-trade Grid Regression suite passes.
- No test submits a trade request.
- Implementation report maps each acceptance criterion to code and test evidence.
- CTO code review approves the diff against SPEC, TEST_PLAN and architecture.
- User confirms completion before the WP is marked Done.
