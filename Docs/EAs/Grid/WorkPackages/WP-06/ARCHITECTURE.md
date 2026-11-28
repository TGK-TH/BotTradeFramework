# WP-06 — Production EA Integration Architecture (Design Draft)

สถานะ: CTO Design Draft — 2026-11-27
ไม่ใช่ Implementation Authorization

## 1. Runtime Composition

```text
Grid V1 EA (.mq5)
  ├─ Inputs / Configuration Validator
  ├─ CTGKGridIdentity
  ├─ CTGKGridLifecycle + CTGKGridRuntimeOrchestrator
  ├─ CTGKGridEntryMappingSnapshotStorage + CTGKGridEntryMappingReducer
  ├─ CTGKGridLevelEngine + CTGKGridLevelRuntimeCoordinator
  ├─ CTGKGridEntryExecutionAdapter + CTGKGridEntryExecutionPipeline
  ├─ Trade Event / Deal Correlation Bridge (new integration)
  ├─ CTGKGridOpenPositionAcquirer + CTGKGridOpenPositionReconciliation
  ├─ CTGKGridOrderExecutionAdapter (reset/close only; current capability)
  └─ Strategy Tester diagnostics / scenario telemetry
```

The EA owns lifecycle ordering and event serialization. Pure Engine/Policy and reusable adapters must not become a second state authority.

## 2. Initialization Order (proposed)
1. Validate chart Symbol and user Inputs; validate symbol trading constraints (volume min/max/step, tick size/digits as execution requirements) without mutating account state.
2. Initialize system-managed Grid Identity and Magic for the chart instance.
3. Initialize canonical Mapping Snapshot Storage and recover committed Snapshot + Journal.
4. Initialize Reducer and replay durable records; validate identity/config/schema.
5. Initialize Lifecycle persistence and Runtime restoration under the approved precedence contract.
6. Initialize live Open Position Source / stable Snapshot Acquirer and WP-05C reconciliation adapter.
7. Hydrate Coordinator from canonical Reducer Projection; keep Entry/Candidate gate closed until successful complete/stable reconciliation.
8. Initialize CTrade entry/close ports with synchronous mode and exact Symbol/Magic.
9. Initialize the event/correlation bridge and quote baseline.
10. Enter READY/WAIT_INITIAL_ENTRY only if every required gate is released; otherwise enter visible Recovery/Error state and block new entries.

Exact precedence between the legacy Lifecycle Snapshot and canonical Mapping Reducer persisted configuration must be explicitly validated. Do not independently initialize two conflicting configuration authorities.

## 3. Event Model (proposed)
- `OnInit`: bounded bootstrap only; no new trade request.
- `OnTick`: read current Bid/Ask, process queued trade evidence/reconciliation first, manage existing owned positions, then evaluate at most one new candidate if all gates are open and price is within Bounds.
- `OnTradeTransaction`: capture relevant transaction identifiers and mark evidence dirty; avoid applying a stale or incomplete event directly to canonical state.
- Deal correlation: resolve actual entry Deals by exact Order Ticket from durable Entry Intent/Execution Result; validate Symbol, Magic, Deal Entry type, Order ticket, Position Identifier, volume and fill price. Append Deal Association idempotently before Position Reconciliation can accept the Position.
- If event ordering is uncertain or event callback arrives before the Request/Order correlation is available, retain a pending evidence flag and perform a bounded history scan on the next serialized processing point. Never guess by Comment, approximate price or time proximity.
- The Open Positions Acquirer must capture and consume its complete/stable Snapshot within the same serialized EA event, against the exact Reducer sequence.
- Reconcile before requesting another Entry. One unresolved Request per Instance remains enforced.

This is a proposed event architecture, not yet a final choice between event-driven and polling-assisted correlation. WP-06B must prove the exact MT5 Strategy Tester callback/order semantics and select the minimal deterministic approach.

## 4. Entry Lifecycle

### Initial Anchor
- Start only when no prior durable Grid exists and no owned Position is present.
- Wait while executable-side quote is outside [LowerBound, UpperBound].
- Persist initial-entry intent before sending the market request.
- Resolve actual entry Deal(s) and Position Identifier from exact order/deal evidence.
- Confirm one supported Position Identifier under the current contract.
- Use actual fill price to initialize Anchor and grid geometry.
- Atomically establish canonical config, Anchor state, and Position Mapping; release entry gate only after durable commit and complete/stable Position evidence.
- If the request is rejected/terminal without Position, remain waiting for initial entry. If evidence conflicts or is incomplete, fail closed.

### Normal Grid Entry
- Obtain current quote and call Coordinator UpdatePrice.
- If a candidate is offered, construct the exact execution candidate with Instance/Symbol/Magic/Mode/Config Epoch/Target/Entry Price.
- Pass through Resolver → Policy → Entry Adapter → Coordinator request result.
- Persist Intent before request. Accepted/PLACED remains unresolved.
- Correlate entry Deal(s), append Deal Association, acquire stable Positions snapshot, run WP-05C reconciliation, hydrate/release gate and only then accept ACTIVE.
- No second request while the previous request remains unresolved.

## 5. Position Management / Reset
- Every serialized tick must keep managing existing owned Positions even when price is outside Bounds or new-entry gate is blocked, provided management path is safe.
- Existing reset/close adapter is called only when Runtime explicitly reports CLOSE_REQUIRED and must filter exact Symbol + Magic.
- After close attempt, obtain a fresh stable snapshot and reconcile; only then may reset rebuild / new configuration proceed.
- Apply the previously approved broker-side per-Position TP: BUY actual fill + 1 × GridStep; SELL actual fill − 1 × GridStep; no Basket TP. Existing Positions retain their current TP; new Positions use the current GridStep. After TP, the level must wait for price to retouch/cross the original Entry Level before re-entry.
- Current canonical Full Close reconciliation remains reason-free and does not classify TP/SL/manual reasons. CTO must prove the Level/quote state transition reproduces the TP re-entry rule without close-reason inference.
- Partial Close retains ACTIVE while Position volume remains positive; Full Close occurs only when the Position Identifier is absent from a complete/stable Snapshot.

## 6. Safety / Recovery
- Any identity/configuration mismatch, storage error, unstable/invalid snapshot, orphan owned Position, duplicate/conflicting deal evidence, or unsupported multi-Position evidence blocks new entries.
- No recovery by approximate price matching, comments, or order-time heuristics.
- Existing owned Positions must not be abandoned merely because new entries are blocked; continue safe observation/management or expose a clear Recovery Required state.
- Do not close foreign positions.
- No hidden automatic cleanup on OnDeinit.
- OnDeinit performs only safe resource/logging cleanup; it must not delete committed trading state.

## 7. Observability
At minimum log instance, symbol, magic, state, config epoch, request ID, order/deal ticket, position identifier, candidate target, reconciliation generation/base sequence, and explicit reason for each gate/error. Avoid converting 64-bit identifiers to floating point.

## 8. CTO Design Review Addendum

### Deal Evidence Intake
OnTradeTransaction is a short notification path: enqueue relevant 64-bit Deal Tickets, then process History evidence serially outside the callback. Correlate only through exact DEAL_ORDER == persisted Order Ticket. CTrade ResultDeal is a hint, not the sole source. A bounded exact-order History scan is required for missed callbacks, queue overflow and recovery of a known unresolved Order Ticket. Persist unique Deal Associations before WP-05C. Product Owner authorized preparation of the separate [D-06-02 Minimal Strategy Tester Probe](D-06-02_PROBE/SPEC.md) and [TEST_PLAN](D-06-02_PROBE/TEST_PLAN.md); actual Tester execution requires a separate explicit approval. The Probe's same-run cold-state recovery simulation is not a true EA/Terminal restart. If the selected Tester build cannot demonstrate a genuine restart path, record true restart recovery as NOT_TESTED and keep that acceptance open.

### Deal Evidence Persistence
The current Reducer Deal projection stores Request ID, Deal Ticket, Position Identifier and volume only, and rejects any repeated Deal Ticket. It cannot independently reconstruct a volume-weighted Anchor after restart or distinguish an identical replay from conflicting evidence. WP-06B must version the Deal Association payload/projection to retain exact Order Ticket, Symbol, Magic, Deal Entry type, Position Identifier, volume and Deal price. Identical duplicate evidence is a no-op; conflicting evidence for the same Deal Ticket is Recovery Error.

### Initial Bootstrap
Fresh initial entry is a distinct pre-configuration flow. Persist Initial Entry Intent, obtain exact Order/Deal evidence and a complete/stable Position snapshot, then commit one compound Initial Bootstrap journal record containing canonical config, actual Anchor, geometry, Anchor mapping and ACTIVE. This requires a narrowly scoped Reducer/Journal schema amendment; separate Lifecycle and Reducer writes are not atomic. No normal candidate processing before commit.

### Configuration Authority
Canonical Mapping Reducer Snapshot + Journal owns trading configuration and geometry. Extend it to include Fixed Lot. Lifecycle Persistence owns orchestration/reset metadata; overlapping legacy values are mirrors validated against canonical projection. Any mismatch fails closed. Explicit migration is required for old snapshots lacking canonical Fixed Lot.

## 9. Approved Design Decisions and Remaining Proof

### Product Owner-approved design contracts
- D-06-01: per-Position broker-side TP contract is resolved; WP-06D verifies the reason-free Full Close state contract preserves retouch-before-reentry behavior.
- D-06-03: typed Initial Entry Intent and one atomic Initial Bootstrap journal record, including actual fill-derived Anchor, canonical config/Fixed Lot, Config Epoch, geometry, Anchor Position Mapping and ACTIVE; approved 2026-11-27. Design approval only; implementation is not authorized.
- D-06-04: canonical Mapping Reducer Snapshot/Journal is the sole trading configuration/geometry authority and persists Fixed Lot; Lifecycle owns orchestration metadata and duplicate mirrors fail closed; approved 2026-11-27. Design approval only; implementation is not authorized.
- D-06-02: Product Owner authorized preparation of the separate diagnostic Probe on 2026-11-28. Probe SPEC/TEST_PLAN are prepared; Trello card #24 is in Ready. Source implementation awaits user-selected Implementer and explicit implementation authorization. Running the Probe and sending its one Tester-only Market Request requires separate explicit approval after Compile.

### Open proof / decisions
1. D-06-02: capture real Tester callback sequence, immediate/deferred History behavior, exact Order-to-Deal enumeration, Deal property availability, and partial-fill behavior where naturally supported. Same-run cold-state recovery simulation is not true EA/Terminal restart; record TRUE_RESTART_RECOVERY=NOT_TESTED unless a genuine restart path is demonstrated.
2. D-06-05: verify exact Tester Hedging execution contract (account mode, execution/filling mode, symbol volume constraints, tick model, Order/Deal/Position evidence). Multiple Position Identifiers for one Order stops the current one-Request-to-one-Position flow and triggers architecture review.
3. D-06-06: define and prove realistic restart/recovery coverage within an actually supported test environment; do not treat object reinitialization or same-process reload as a real restart.

### Current execution boundaries
- WP-06A/B/C Production implementation is not authorized by the Probe preparation approval.
- Unit Tests remain no-trade. Only the separately approved Probe may send its single Market Request, and only inside Strategy Tester.
- No Demo/Live execution, no close/modify request, no commit/push without explicit Product Owner authorization.
- User selects Codex or Freebuff as Implementer. Fresh no-trade Grid Regression baseline PASS and explicit implementation authorization are required before source changes.