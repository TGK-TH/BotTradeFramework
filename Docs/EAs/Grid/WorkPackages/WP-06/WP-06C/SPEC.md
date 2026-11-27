# WP-06C — Initial Anchor & Grid Entry Runtime

สถานะ: CTO Design Draft — implementation not authorized

## Objective
Connect the approved initial-entry and normal Grid candidate flows to the existing Entry Execution Pipeline so a Grid can establish its first real Anchor and subsequently open one Position per eligible Grid Level under the supported current contract.

## Scope
- Initial Entry wait logic using executable-side quote and hard Bounds.
- Persist initial-entry intent before market request.
- After exact Deal/Position evidence is correlated, bootstrap Anchor from actual fill price and exact Position Identifier.
- Define and implement one atomic canonical persistence transition for initial Anchor configuration + Anchor Mapping + Anchor ACTIVE; no partial Anchor or mapping state.
- Initialize two-sided Engine/Coordinator geometry only from the actual Anchor fill and approved config.
- Normal tick flow: obtain current Bid/Ask; call Coordinator UpdatePrice; process at most one candidate per price check.
- Construct exact execution candidate provenance and route Candidate → Resolver → Policy → Entry Adapter → Coordinator request result.
- Ensure accepted/placed requests remain unresolved until WP-06B evidence + WP-05C stable Position reconciliation.
- Prevent duplicate requests while unresolved; preserve deferred candidate selection behavior.
- Keep all new-entry checks within Bounds and continue existing Position management when outside Bounds.
- Add minimal runtime diagnostics for candidate, target, request, order/deal, mapping and state transitions.

## Out of Scope
- TP/SL/close management and reset.
- Multi-Position-per-Request architecture.
- Changes to existing Engine selection rules, Grid geometry, Entry Policy eligibility or Bounds semantics.
- Demo/Live trading.
- Rewriting Reducer/Storage schema without an approved architecture amendment.

## Dependencies
- WP-06A bootstrap/recovery gate.
- WP-06B exact Deal Association intake.
- D-06-03 initial Anchor durable bootstrap design.
- Current one Request : one Position Identifier contract, proven for the selected Tester configuration.

## Acceptance Criteria
- Fresh Grid waits outside Bounds and sends no request.
- Initial BUY/SELL request is sent only inside Bounds and only once.
- Anchor equals actual fill price; never requested/current quote approximation.
- Anchor mapping and ACTIVE state become visible only after exact Deal + Position evidence and atomic durable commit.
- Engine/Coordinator levels are built from the actual Anchor and approved Step/Bounds.
- Normal Grid entries use the existing Coordinator → Resolver → Policy → Adapter pipeline.
- At most one candidate is executed per price check; BUY/SELL candidate priority matches existing Engine contract.
- No duplicate request while unresolved; no premature ACTIVE.
- Bounds block new entries only; existing owned Position management is not disabled.
- Dedicated fake-port integration tests and full no-trade regression pass; CTO review APPROVED.
