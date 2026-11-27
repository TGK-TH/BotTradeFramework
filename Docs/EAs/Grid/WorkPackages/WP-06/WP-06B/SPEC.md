# WP-06B — Trade Event Intake & Entry Deal Correlation

สถานะ: CTO Design Draft — implementation not authorized

## Objective
Provide deterministic production intake of MT5 trade events and correlate Entry Deals to the exact durable Entry Request/Order before WP-05C Open Positions Reconciliation consumes live Positions.

## Scope
- Verify Strategy Tester event semantics for `OnTradeTransaction`, transaction types, event ordering and History availability.
- Add a minimal production event bridge that records relevant identifiers / marks evidence dirty; it must not infer Position Mapping from callback order.
- Resolve Entry Deals by exact Order Ticket associated with the durable Entry Intent/Execution Result.
- Validate Deal Entry type, Symbol, Magic, Order Ticket, Deal Ticket, Position Identifier, volume and fill price.
- Persist one Deal Association per unique Entry Deal using the existing Reducer/Journal schema and sequence rules.
- Handle multiple Deals belonging to the same Position Identifier within Requested Volume.
- Deduplicate repeated callbacks and history observations using exact Deal Ticket / reducer idempotency rules.
- Ensure entry evidence is processed before WP-05C Open Position reconciliation.
- Fail closed on missing order correlation, foreign deal, invalid identifier, excess volume, conflicting Position Identifier, or incomplete History read.
- Support initial-entry correlation only after the Initial Anchor bootstrap contract is approved; if schema needs a distinct initial intent, document it before implementation.

## Out of Scope
- Multi-Position-per-Request semantics.
- Position Mapping creation directly from Deal callback.
- Full Close/Closing Deal History and TP/SL/manual classification.
- New Trade Requests or changes to entry policy.
- Demo/Live trade validation.

## Dependencies
- WP-06A shell/event lifecycle design.
- WP-05A/B/C canonical reducer, storage and reconciliation contracts.
- D-06-02 MT5 Tester event/correlation decision.
- Current one-Request-to-one-Position-Identifier contract remains supported; conflicting evidence fails closed.

## Technical Contract
- `OnTradeTransaction` is an evidence notification, not canonical state by itself.
- Only exact durable Request ↔ Order Ticket correlation can authorize Deal Association.
- Use exact 64-bit integer/string identifiers; never convert tickets/identifiers to double.
- Persist Deal Association before the Open Position Snapshot can use it to resolve an unresolved Request.
- Repeated event delivery must not duplicate volume or durable associations.
- Do not use Comment, approximate fill price, time proximity, or magic alone to infer the Request.
- If Tester event ordering is insufficient, use a bounded serialized History reconciliation path and document why.

## Acceptance Criteria
- Each valid Entry Deal is associated with the exact Request and Position Identifier exactly once.
- Multiple partial Deals for one Position Identifier aggregate correctly within Requested Volume.
- Duplicate/out-of-order callbacks are idempotent.
- Invalid/incomplete/conflicting evidence creates no invalid durable association and keeps the gate closed.
- WP-05C can reconcile the matching complete/stable Position Snapshot and only then create Position Mapping / ACTIVE.
- Dedicated Fake History/Event tests and relevant no-trade Regression pass; CTO review APPROVED.
