# WP-06 — Design Decisions / Open Questions

Updated: 2026-11-27 — D-06-03 and D-06-04 approved by Product Owner

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

## D-06-02 — Deal Evidence Intake (CTO recommendation; Tester proof pending)

Recommended design:
1. OnTradeTransaction is a notification trigger only. For relevant DEAL_ADD notifications, capture the 64-bit Deal Ticket in a bounded pending queue (or bounded dirty-evidence set); do not mutate Reducer state or create mappings inside the callback.
2. Process evidence serially from the EA event loop. Select the exact Deal Ticket from History and read DEAL_ORDER, DEAL_ENTRY, DEAL_TYPE, DEAL_SYMBOL, DEAL_MAGIC, DEAL_POSITION_ID, DEAL_VOLUME and DEAL_PRICE.
3. Match DEAL_ORDER exactly to the durable Order Ticket in the one unresolved accepted Execution Result. Validate all properties against the Instance Symbol/Magic and supported entry direction.
4. Append one Deal Association per unique Deal Ticket before WP-05C may reconcile the matching live Position. The current Reducer stores only Request ID, Deal Ticket, Position Identifier and volume, and rejects every duplicate Deal Ticket. WP-06B must add a versioned evidence projection with exact Order Ticket, Symbol, Magic, Deal Entry type, Position Identifier, volume and Deal price; identical duplicate evidence becomes a no-op, conflicting evidence becomes Recovery Error.
5. Add bounded recovery when callback delivery is missed, the queue overflows, or the EA restarts with an unresolved Request. Select the History Order by its exact persisted Order Ticket, derive its setup time, scan a bounded History interval through now, and filter every candidate Deal by exact DEAL_ORDER.
6. If exact History selection or required property reads fail, do not infer that no fill exists. Keep the gate closed; retry only through a deterministic bounded policy, then enter Recovery Error.

CTrade ResultDeal is a hint only, not the sole source of truth. Enumerate all Deals for the exact Order to support partial fills. Duplicate callback/History observations must be idempotent; a repeated Deal Ticket with conflicting properties is a recovery conflict, never an overwrite. Multiple Deals may aggregate only when all share one Position Identifier and do not exceed Requested Volume. More than one Position Identifier per Request remains unsupported and fails closed.

Event ordering is not a correctness guarantee. Exact Deal Ticket and exact Order Ticket are the correlation keys. The Tester integration trace must prove callback delivery, History selection, exact Order-to-Deal enumeration and restart fallback. This recommendation is not yet a verified MT5 guarantee.

Status: recommended design selected for planning; D-06-02 remains open until approved Tester evidence proves the behavior.

## D-06-03 — Initial Anchor Durable Bootstrap (Product Owner approved)

A fresh Grid needs a distinct pre-configuration initial-entry lifecycle:
1. Persist a distinguishable Initial Entry Intent before sending the first market request; it must not require a fabricated Anchor or pre-existing Grid geometry.
2. Persist execution outcome and exact Order Ticket.
3. Correlate and persist all Entry Deals through D-06-02, including actual Deal prices. Confirm one supported Position Identifier and consistent aggregate volume.
4. Acquire a complete/stable Open Positions snapshot matching exact Symbol/Magic/Identifier.
5. Append one atomic canonical Initial Bootstrap journal record. It establishes Mode, Bounds, Grid Step, Fixed Lot, volume-weighted actual Anchor fill price, Config Epoch, level geometry, Anchor Position Mapping and Anchor ACTIVE together.
6. Reducer validates and applies the compound transition transactionally. Append/flush one journal record before in-memory commit. Any failure keeps the gate closed; no independent Lifecycle save and Reducer save may simulate atomicity.
7. Normal candidate processing starts only after the atomic commit and projection validation.

This requires a narrowly scoped Reducer/Journal schema amendment. Do not emulate it with RESET_COMMITTED or a normal Entry Intent that assumes Config Epoch already exists. If multiple Deals contribute to one Position Identifier, proposed Anchor is the volume-weighted average of actual DEAL_PRICE values, normalized to Symbol tick precision and checked against the Position average open price. Any mismatch fails closed.

Status: APPROVED by Product Owner on 2026-11-27. Implement only through the scoped, versioned Reducer/Journal amendment specified in WP-06C. This approval is design approval, not implementation authorization.

## D-06-04 — Configuration Authority (Product Owner approved)

- Canonical Mapping Reducer Snapshot + Journal owns trading configuration and geometry: Instance/Symbol/Magic, Mode, Bounds, Grid Step, Anchor, level geometry/count, Config Epoch, Level state, Deal Associations and Position Mappings.
- Extend canonical persisted configuration to include Fixed Lot. It affects future order sizing and must not remain an independently mutable Lifecycle-only value.
- Lifecycle Persistence owns orchestration metadata only: lifecycle state, reset reason, pending requested Mode/Step/Magic and transition bookkeeping.
- Legacy duplicated Lifecycle Mode/Step/Anchor/Level Count are mirrors/checksums, not a second source of truth. Restore compares them with canonical projection; any disagreement is Recovery Error.
- Config Epoch advances only through a committed canonical configuration transition. Runtime/Coordinator hydrate from that projection.
- Changed Inputs request Lifecycle/reset orchestration; they do not mutate canonical configuration until old positions are closed and canonical reset commit succeeds.
- Define explicit schema migration. Missing canonical Fixed Lot must not be silently defaulted when owned positions exist.

Status: APPROVED by Product Owner on 2026-11-27. Implement the authority split and migration policy specified in WP-06A. This approval is design approval, not implementation authorization.

## D-06-05 — Strategy Tester execution contract
Verify supported Tester account mode, execution mode, symbol volume constraints, tick model, partial fill behavior and exact Order/Deal/Position evidence. If one Entry Request can produce multiple Position Identifiers under the supported Tester setup, stop and request architecture revision before continuing.

## Open Decision D-06-06 — Restart Coverage
Define realistic Tester restart/recovery coverage separately from normal single-pass backtest. Do not claim restart resilience from a test that only reinitializes in-memory objects.

## D-06-02 Probe Authorization / Scope Update (2026-11-28)
Product Owner authorized preparation of a minimal Strategy Tester Probe. Probe design is documented in:
- [Probe SPEC](D-06-02_PROBE/SPEC.md)
- [Probe TEST_PLAN](D-06-02_PROBE/TEST_PLAN.md)
- [Trello card #24](https://trello.com/c/7S8Pw7nE/24-d-06-02-minimal-strategy-tester-probe)

The Probe is a separate diagnostic EA, not Production WP-06B code. It may send at most one Market Request per unique Session, only when running in Strategy Tester with an explicit enable input and all Hedging/symbol/volume/Magic safety gates passing. The default input must not send a request. Actual Tester execution requires a separate explicit Product Owner approval after Source Compile.

Important limitation found during official MQL5 documentation review: chart operations, including `ChartSetSymbolPeriod()`, have no effect in Strategy Tester. Therefore the Probe cannot use chart switching to claim a genuine EA reinitialization/restart. It will test a cold-state recovery simulation by clearing volatile callback state and reloading the persisted decimal-string Order Ticket within the same Tester run. This is not a true EA/Terminal restart. If a genuine restart path cannot be demonstrated, true restart recovery remains NOT_TESTED and D-06-02/D-06-06 must not be marked fully proven on that basis.

Status: Probe scope authorized for preparation; Probe implementation/execution gates remain separate.
