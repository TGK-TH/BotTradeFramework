# WP-05A.2 — Anchor State Transitions

**Status: APPROVED — Product Owner approval received 2026-11-23**
**Implementation gate: Authorized scope is fixed; source changes remain blocked until the user reports the pre-change Grid Regression Baseline.**
**Parent:** WP-05A — Persistence Foundation  
**Depends on:** WP-05A.1 — Anchor State Model

## 1. Purpose

Define the deterministic and durable state transitions for Anchor and Grid Level Position mappings when an entry is confirmed, partially closed, or fully closed.

The design removes TP/Non-TP close classification from Grid state transitions. Full-close detection is supplied by a future authoritative Position Reconciliation layer; this work package does not read MT5 Deal History or enumerate live account positions.

## 2. Scope

### In scope

- Anchor state activation when its Position Mapping is confirmed.
- Partial-close behavior for Anchor and normal Grid Level mappings.
- Full-close reducer transition for Anchor and normal Grid Level mappings.
- Atomic persistence of Position Mapping removal and corresponding Anchor/Level state update.
- Durable idempotency based on the existing Position Mapping and ordered Journal.
- Consolidation of operational `WAIT_RETURN` into `READY`.
- Replay/serialization compatibility for already-written V1 records and state values.
- Reducer, Engine, persistence-boundary and unit-test changes needed for the above contract.

### Explicitly out of scope

- MT5 account scanning / `PositionsTotal()` adapter implementation.
- Complete/stable Open Positions snapshot acquisition.
- Production `OnTradeTransaction` wiring.
- Deal History ingestion for close detection, TP/SL classification or close-price extraction.
- Runtime order execution and any live/demo trade operation.
- Changes to Grid entry selection, crossing direction, bounds, lot sizing or other trading behavior.

The future Position Reconciliation work package (WP-05C) must produce confirmed reconciliation facts and call this durable transition contract. Entry Deal Association currently used by the existing entry pipeline remains unchanged; this decision removes the need for closing Deals to detect a Full Close, not the existing entry-fill correlation mechanism.

## 3. Canonical Position Identity

1. **Position Identifier** is the canonical identity of one MT5 position lifecycle.
2. **Position Ticket** is an operational handle and may be refreshed; it is not the close-event identity.
3. A close transition is scoped by the Grid Instance and the currently mapped Position Identifier.
4. The reducer must locate exactly one current mapping by Position Identifier before applying a new Full Close transition.
5. A Position Identifier must never be inferred from a logical Level, approximate price, Order Ticket or Deal Ticket.

The Position Mapping already stores Position Identifier, Position Ticket and remaining Volume. These remain canonical durable fields.

## 4. State Model

The operational states are:

- `READY`: no Position is mapped; the Level may be selected when the Engine's crossing rules are met.
- `ACTIVE`: a confirmed Position Mapping exists.
- `WAIT_ACTIVATION`: the market must cross back through the Level in the activation direction before the Level becomes READY.

`WAIT_RETURN` is removed as an operational state. Existing code paths already treat `READY` and `WAIT_RETURN` identically for entry eligibility, entry-intent validation and execution policy. Their only meaningful difference was the TP-dependent label written after a close.

### Legacy serialized value

The former numeric value assigned to `WAIT_RETURN` must not be reused. Preserve the numeric slot as a legacy/reserved value and preserve the existing numeric value of `WAIT_ACTIVATION`. On load/replay, legacy `WAIT_RETURN` is normalized to `READY`. New writes must never emit `WAIT_RETURN`.

This is a value normalization within the existing V1 state shape, not a new state and not a request to support the older snapshot shape that omitted the required Anchor State.

## 5. State Transition Contract

### 5.1 Entry confirmation

- An Entry Request Accepted result is not sufficient to set a state to ACTIVE.
- A Deal Association alone is not sufficient.
- When a valid Position Mapping is durably confirmed:
  - normal Level: set that Level to `ACTIVE`;
  - Anchor: set Anchor State to `ACTIVE`.
- The Position Mapping and its ACTIVE state must be applied as one reducer event / logical transition.

### 5.2 Partial Close

A Position remains present with a positive remaining Volume.

- Update the mapped Position's remaining Volume.
- Refresh Position Ticket if the broker reports a changed ticket.
- Keep the corresponding Anchor/Level state `ACTIVE`.
- Do not change state based on TP, SL, manual close, close price or partial-close count.
- A partial-close observation must not remove the Position Mapping.

The durable update of Position metadata should be represented by one reconciliation record where practical, so Ticket and Volume cannot describe different observations.

### 5.3 Full Close

A Full Close is confirmed by the future reconciliation layer when a previously mapped Position Identifier is absent from an authoritative complete Open Positions snapshot.

The reducer receives the confirmed Position Identifier and the computed post-close state. It does not inspect Deals and does not infer the close reason.

For the corresponding Anchor or Level, compute the next state using the current Grid direction and current executable-side quote:

- BUY uses current Ask:
  - if `level_price >= current_ask`, next state is `WAIT_ACTIVATION`;
  - otherwise next state is `READY`.
- SELL uses current Bid:
  - if `level_price <= current_bid`, next state is `WAIT_ACTIVATION`;
  - otherwise next state is `READY`.

Equality is treated as the wrong-side case, matching the current `IsWrongSideAfterEntryMove()` behavior.

The activation crossing remains unchanged:

- BUY: `WAIT_ACTIVATION` becomes `READY` after an upward crossing through the Level.
- SELL: `WAIT_ACTIVATION` becomes `READY` after a downward crossing through the Level.

No TP/Non-TP branch exists in the new transition contract.

### 5.4 Anchor and normal Level parity

Anchor follows the same ACTIVE / partial-close / full-close lifecycle as a normal Level, using Anchor Price in place of Level Price. Anchor State is not a separate persistence authority; it remains part of the canonical Entry Mapping Reducer snapshot and Journal.

## 6. Durable Event and Atomicity Contract

### 6.1 Full-close event

The new canonical Full Close lifecycle payload identifies the Position Identifier and the computed next state. The reducer obtains the target kind, logical Level index, request association and current ticket from the existing mapping.

One Journal record must atomically:

1. validate the exact currently mapped Position Identifier;
2. remove that Position Mapping;
3. remove associated transient Deal Associations and completed Request state as currently required;
4. update the corresponding normal Level State or Anchor State to `READY` or `WAIT_ACTIVATION`;
5. advance the Journal sequence only through the normal append/replay contract.

No separate processed-close registry is introduced.

### 6.2 Partial-close event

One lifecycle record updates the Position Mapping's remaining Volume and refreshed Ticket. It must preserve the mapping and ACTIVE state.

### 6.3 Failure behavior

- Invalid payload, unknown Position Identifier, mismatched target or impossible state transition: reject and mark recovery error according to the existing reducer failure policy.
- Storage Append/Flush failure: no success result and no in-memory state transition.
- Crash after durable append but before in-memory application: replay applies the record.
- Crash before durable append: replay retains the previous mapping; the next authoritative reconciliation can emit the transition again.
- Reducer application failure after append: enter Recovery Required; do not continue trading. Recovery must replay the durable record and validate the resulting state.

The reducer must validate all preconditions before mutating arrays or state so a failed application cannot leave a partially applied in-memory transition.

## 7. Idempotency Contract

Idempotency is state-based; no unbounded Processed Deal / Processed Close Event registry is required.

1. The reconciliation adapter emits a Full Close record only when the exact Position Identifier is currently present in the durable mapping.
2. Once the close record is durably applied, that mapping no longer exists.
3. Reprocessing the same complete Open Positions snapshot therefore finds no mapping for that Position Identifier and emits no second close transition.
4. Journal sequence numbers provide durable ordered application and replay; a committed record is replayed once at its sequence.
5. A repeated close record with a new Journal sequence and no matching mapping is invalid, not a second successful close.
6. If the same logical Level later receives a new Position with a different Position Identifier, an old close observation must never remove or mutate the new mapping.
7. If the reconciliation layer sees a live owned Position that has no matching mapping or valid unresolved entry request, it must fail closed rather than infer the Level mapping.

The future reconciliation adapter must acquire and consume each complete snapshot synchronously in one serialized EA event. It must not queue, replay or apply stale snapshots after a later reconciliation or entry confirmation. A snapshot that cannot be proven complete/stable is not eligible to cause a Full Close transition.

## 8. Open Positions Reconciliation Boundary (for WP-05C)

WP-05A.2 consumes confirmed facts; WP-05C owns the MT5 adapter. The WP-05C contract must include:

- Enumerate all account positions; any failed ticket selection or property read invalidates the whole snapshot.
- Capture Position Identifier, Position Ticket, Symbol, Magic Number and Volume.
- Verify the scan is complete and stable before comparing it with durable mappings. A practical implementation is two consecutive full scans whose position sets and relevant fields agree; if they differ, retry without state mutation.
- Filter ownership by exact Symbol + Magic Number only after successful account enumeration.
- Match by Position Identifier; use Position Ticket only as a refreshable handle.
- Lower Volume means Partial Close; unchanged Volume means no state change; increased Volume for the same Hedging Position is conflicting evidence and fails closed.
- A mapped Position absent from a complete stable snapshot means Full Close.
- An owned live Position without a durable mapping or valid unresolved request is an orphan and fails closed.
- Snapshot acquisition failure, instability or incomplete enumeration must never be interpreted as all positions closed.

An Open Positions snapshot cannot reconstruct a position that opened and closed entirely while the EA was offline or between observations, nor can it provide exact close reason, close price, or individual partial-close history. These details are intentionally not required by the approved Grid state behavior.

## 9. Schema and Replay Compatibility

- Keep the outer mapping Journal / Snapshot schema at V1 unless implementation discovers a concrete serialized-shape change that cannot be handled by deterministic normalization.
- Preserve the existing required Anchor State field and Fail Closed behavior for snapshots missing it.
- Normalize legacy `WAIT_RETURN` state values to `READY` when replaying old lifecycle records or loading existing persisted state.
- Preserve the numeric value of `WAIT_ACTIVATION`; do not reuse the old `WAIT_RETURN` numeric slot.
- Continue to replay existing V1 entry-intent, execution-result, Deal Association, Position Mapping, Position Volume, Position Ticket and Reset records.
- Legacy `POSITION_CLOSED` payloads containing TP/NON_TP are read only for replay compatibility. Their TP distinction is ignored for state semantics; legacy `WAIT_RETURN` is normalized to `READY`. New writes must use the reason-free payload.
- Legacy Anchor close records that did not persist a post-close Anchor State require a deterministic normalization to `READY`; the implementation must document and test this compatibility path. No missing-Anchor-State snapshot is accepted.

## 10. Acceptance Criteria

- Anchor mapping confirmation durably sets Anchor State ACTIVE.
- Normal Level mapping confirmation continues to set Level State ACTIVE.
- Partial close updates Volume / Ticket and leaves Anchor/Level ACTIVE.
- Full close removes the exact mapping and updates the corresponding state in one Journal record.
- TP, SL and manual close reasons produce identical state transitions for the same current quote.
- BUY/SELL wrong-side and activation-crossing rules remain unchanged.
- WAIT_RETURN is never emitted by new writes and is normalized to READY on legacy replay/load.
- Duplicate complete snapshots do not append duplicate close transitions.
- Restart/replay after each crash boundary converges to the same canonical state.
- An old close observation cannot mutate a newly mapped Position at the same logical Level.
- Invalid or conflicting evidence fails closed without a partial in-memory mutation.
- No MT5 Deal History close lookup is introduced.
- No test sends a trade request.

## 11. Implementation Gate

Product Owner approval of this SPEC and TEST_PLAN was received on 2026-11-23. Freebuff is authorized to implement the exact scope in `IMPLEMENTATION_TASK.md` only after the user reports the pre-change Grid Regression Baseline. Until that baseline is reported, no source changes are authorized.
