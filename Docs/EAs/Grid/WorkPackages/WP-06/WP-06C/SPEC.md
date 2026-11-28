# WP-06C — Initial Anchor & Grid Entry Runtime

สถานะ: CTO Design — D-06-03 approved by Product Owner; implementation not authorized

## Objective
Connect the approved initial-entry and normal Grid candidate flows to the existing Entry Execution Pipeline so a Grid can establish its first real Anchor and subsequently open one Position per eligible Grid Level under the supported current contract.

## Scope
- Initial Entry wait logic using executable-side quote and hard Bounds.
- Persist initial-entry intent before market request.
- After exact Deal/Position evidence is correlated, bootstrap Anchor from actual fill price and exact Position Identifier.
- Define and implement one atomic canonical persistence transition for initial Anchor configuration + Anchor Mapping + Anchor ACTIVE; no partial Anchor or mapping state.
- Initialize two-sided Engine/Coordinator geometry only from the actual Anchor fill and approved config.
- Normal tick flow: drain queued trade evidence / bounded History recovery, persist Deal Associations, acquire a complete/stable Position snapshot and run WP-05C reconciliation first; only then obtain current Bid/Ask, call Coordinator UpdatePrice and process at most one candidate per price check.
- Construct exact execution candidate provenance and route Candidate → Resolver → Policy → Entry Adapter → Coordinator request result.
- Ensure accepted/placed requests remain unresolved until WP-06B evidence + WP-05C stable Position reconciliation.
- Prevent duplicate requests while unresolved; preserve deferred candidate selection behavior.
- Keep all new-entry checks within Bounds and continue existing Position management when outside Bounds.
- Add minimal runtime diagnostics for candidate, target, request, order/deal, mapping and state transitions.

## Approved Initial Bootstrap Contract — D-06-03

### Pre-Configuration Initial Intent
- A fresh instance is eligible for `WAIT_INITIAL_ENTRY` only after WP-06A proves there is no prior canonical Grid state, no owned live Position and no unresolved Request.
- When executable-side quote is inside inclusive Bounds, persist a typed Initial Entry Intent before invoking the Entry Adapter. This intent is explicitly marked as `INITIAL_ENTRY`; it does not require an Anchor, Level ID, normal Grid Config Epoch or initialized Grid geometry.
- Persist the Execution Result and exact Order Ticket using the durable request lifecycle. Accepted/placed is not a fill. While unresolved, suppress all additional entry requests.
- A rejected/terminal no-fill request may return to `WAIT_INITIAL_ENTRY` only when authoritative execution and exact-order History evidence prove that no Entry Deal exists. Failed/incomplete History access is not proof of no fill.

### Evidence and Atomic Bootstrap
1. WP-06B correlates every Entry Deal by exact Order Ticket. All contributing Deals must refer to the same supported Position Identifier; aggregate volume must equal the live Position volume within the platform's volume-step precision and must not exceed Requested Volume.
2. Acquire a complete/stable Open Positions snapshot and prove the Position matches the exact Instance Symbol, Magic and Position Identifier. No Comment/price/time heuristic is permitted.
3. Calculate Anchor from actual Deal evidence. For one Deal, use its actual `DEAL_PRICE`. For multiple partial Deals of the same Position Identifier, use `sum(DEAL_PRICE × DEAL_VOLUME) / sum(DEAL_VOLUME)`, then normalize to Symbol tick precision. Compare against the broker/Tester Position average open price within one Symbol tick; mismatch is Recovery Error. Never use request quote, current Bid/Ask or `CTrade.ResultPrice` as a substitute for persisted Deal evidence.
4. Append one typed, versioned Initial Bootstrap journal record. The compound payload contains the Initial Request ID, exact Order/Deal evidence references, Position Identifier, Mode, Bounds, Grid Step, Fixed Lot, actual Anchor, new Config Epoch, deterministic level geometry, Anchor Position Mapping and Anchor `ACTIVE` transition.
5. Reducer validates every sub-transition against a temporary/backup projection before persistence. Append and flush the single compound journal record, then publish the new in-memory projection atomically. If append/flush fails, no in-memory state changes. If publication fails after a durable append, keep all runtime gates closed and rebuild by replaying the durable record; never attempt a second bootstrap record or expose partial state.
6. Only after durable commit, successful projection validation and runtime hydration may normal Grid candidate processing begin.

The Initial Intent and Initial Bootstrap are distinct journal semantics; do not emulate them using `RESET_COMMITTED`, a normal Grid Entry Intent or separate Lifecycle/Reducer writes. This is a narrowly scoped, approved Reducer/Journal schema amendment. The current one-Request-to-one-Position-Identifier limit remains in force; a second Identifier fails closed.

## Out of Scope
- TP/SL/close management and reset.
- Multi-Position-per-Request architecture.
- Changes to existing Engine selection rules, Grid geometry, Entry Policy eligibility or Bounds semantics.
- Demo/Live trading.
- Reducer/Storage schema changes outside the approved D-06-03 Initial Intent/Bootstrap and D-06-04 canonical configuration amendments.

## Dependencies
- WP-06A bootstrap/recovery gate.
- WP-06B exact Deal Association intake.
- D-06-03 Initial Entry Intent / atomic Bootstrap schema amendment (approved by Product Owner).
- Current one Request : one Position Identifier contract, proven for the selected Tester configuration.

## Acceptance Criteria
- Fresh Grid waits outside Bounds and sends no request.
- Initial BUY/SELL request is sent only inside Bounds and only once.
- Anchor equals the actual Deal fill price, or the volume-weighted average of actual partial Deal fills for the same Position Identifier; never requested/current quote approximation.
- Anchor mapping and ACTIVE state become visible only after exact Deal + Position evidence and atomic durable commit.
- Engine/Coordinator levels are built from the actual Anchor and approved Step/Bounds.
- Normal Grid entries use the existing Coordinator → Resolver → Policy → Adapter pipeline.
- At most one candidate is executed per price check; BUY/SELL candidate priority matches existing Engine contract.
- No duplicate request while unresolved; no premature ACTIVE.
- Bounds block new entries only; existing owned Position management is not disabled.
- Dedicated fake-port integration tests and full no-trade regression pass; CTO review APPROVED.
