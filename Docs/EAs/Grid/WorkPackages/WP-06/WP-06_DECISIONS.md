# WP-06 — Design Decisions / Open Questions

Updated: 2026-11-27

## Confirmed Constraints
- Immediate objective is operational Grid V1 in MT5 Strategy Tester, not Demo readiness.
- MT5 Hedging is the intended Grid V1 account model.
- Chart Symbol only; system-managed Instance ID/Magic.
- User Inputs: Upper Bound, Lower Bound, Grid Mode BUY/SELL, Grid Step, Fixed Lot.
- Initial Entry only within Bounds; actual first fill establishes Anchor.
- Bounds outside market block new entries only; existing Position management continues.
- One Entry Request per Instance at a time; accepted result is not Fill confirmation.
- Current supported mapping contract is one Entry Request to one Position Identifier. Any conflicting evidence fails closed.
- Multi-Position Architecture follows Strategy Tester validation and precedes Demo.
- No Unit Test may send Trade Requests; no Demo/Live trade is authorized in WP-06.

## Resolved Decision D-06-01 — TP Contract (existing Product Owner decision)
The user's previously approved Grid V1 TP contract is:
- TP is per Position, not Basket TP.
- BUY Position TP = that Position's actual Entry Fill Price + 1 × GridStep.
- SELL Position TP = that Position's actual Entry Fill Price − 1 × GridStep.
- TP is broker-side / Position-level; the EA must not replace this with an EA-managed Basket TP.
- The same per-Position rule applies to Anchor and normal Grid Positions.
- After TP closes a Position, the level is eligible for re-entry only when price retouches/crosses the original Entry Level; it must not reopen immediately just because TP closed.
- An already-open Position retains its original broker-side TP if the GridStep input changes; new Positions use the new GridStep. The approved GridStep reset lifecycle still closes old Grid Positions before rebuilding with the new Step.

The canonical WP-05A.2 Full Close transition remains reason-free. TP-specific recycle behavior must be achieved through the existing Level/quote state contract, not by reintroducing Closing Deal History, TP/NON-TP classification, or close-reason persistence. CTO must verify this equivalence in WP-06D tests.

## Open Decision D-06-02 — Deal Evidence Intake (CTO to prove)
Proposed: OnTradeTransaction captures identifiers/dirty state; serialized processing reads authoritative Deal properties by exact Order Ticket, then writes durable Deal Association. A bounded history polling fallback may be needed for missed/early events.
Must be proven against MT5 Strategy Tester event semantics and current Adapter outputs. No assumptions about callback ordering.

## Open Decision D-06-03 — Initial Anchor Durable Bootstrap
The initial market entry has no pre-existing Anchor price/level geometry, while current normal Entry pipeline requires an initialized Coordinator and WP-05C relies on durable Deal Association evidence. Define atomic initial bootstrap using actual fill price + exact Position Identifier, with no partially committed Anchor/Mapping.

## Open Decision D-06-04 — Configuration Authority
Legacy Lifecycle Persistence and canonical Mapping Reducer Snapshot both persist configuration-adjacent state. Define authoritative source and synchronization for Mode, Grid Step, Bounds, Fixed Lot, Anchor, Level Count, Config Epoch; no dual-source drift.

## Open Decision D-06-05 — Strategy Tester execution contract
Verify supported Tester account mode, execution mode, symbol volume constraints, tick model, partial fill behavior and exact Order/Deal/Position evidence. If one Entry Request can produce multiple Position Identifiers under the supported Tester setup, stop and request architecture revision before continuing.

## Open Decision D-06-06 — Restart Coverage
Define realistic Tester restart/recovery coverage separately from normal single-pass backtest. Do not claim restart resilience from a test that only reinitializes in-memory objects.
