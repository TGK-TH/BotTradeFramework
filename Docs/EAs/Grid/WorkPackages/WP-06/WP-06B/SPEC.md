# WP-06B — Trade Event Intake & Entry Deal Correlation

สถานะ: CTO Design — D-06-02 Tester proof pending; implementation not authorized

## Objective
Provide deterministic production intake of MT5 trade events and correlate Entry Deals to the exact durable Entry Request/Order before WP-05C Open Positions Reconciliation consumes live Positions.

## Scope
- Verify Strategy Tester event semantics for `OnTradeTransaction`, transaction types, event ordering and History availability.
- Add a minimal production event bridge that records relevant identifiers / marks evidence dirty; it must not infer Position Mapping from callback order.
- Resolve Entry Deals by exact Order Ticket associated with the durable Entry Intent/Execution Result.
- Validate Deal Entry type, Symbol, Magic, Order Ticket, Deal Ticket, Position Identifier, volume and fill price.
- Persist one Deal Association per unique Deal Ticket. The current Reducer projection stores only Request ID, Deal Ticket, Position Identifier and volume; it is insufficient for weighted-fill Anchor reconstruction and durable conflict comparison. Add a versioned evidence payload/projection containing exact Order Ticket, Symbol, Magic, Deal Entry type, Position Identifier, volume and Deal price. Preserve 64-bit identifiers as decimal strings.
- Before appending a repeated Deal Ticket, compare its complete persisted evidence: identical evidence is a no-op; any differing field is Recovery Error. The current Reducer rejects any duplicate Deal Ticket, so idempotency requires an explicit Reducer/API extension rather than assuming it already exists.
- Handle multiple Deals belonging to the same Position Identifier within Requested Volume.
- Deduplicate repeated callbacks and history observations using exact Deal Ticket / reducer idempotency rules.
- Ensure entry evidence is processed before WP-05C Open Position reconciliation.
- Fail closed on missing order correlation, foreign deal, invalid identifier, excess volume, conflicting Position Identifier, or incomplete History read.
- Support the approved typed `INITIAL_ENTRY` intent from WP-06C. Correlate its Deals through the same exact Order Ticket path and persist complete Deal evidence before the atomic Initial Bootstrap. Initial requests are pre-configuration requests and must not be rejected merely because no normal Grid Config Epoch exists yet; they remain restricted to the explicitly typed initial-request state.

## Out of Scope
- Multi-Position-per-Request semantics.
- Position Mapping creation directly from Deal callback.
- Full Close/Closing Deal History and TP/SL/manual classification.
- New Trade Requests or changes to entry policy.
- Demo/Live trade validation.

## Dependencies
- WP-06A shell/event lifecycle and durable accepted-request state.
- WP-05A/B/C canonical reducer, storage and reconciliation contracts.
- D-06-02 Strategy Tester probe evidence must be approved before production event-bridge implementation.
- WP-06C approved typed Initial Entry Intent / Bootstrap contract.
- Current one-Request-to-one-Position-Identifier contract remains supported; conflicting evidence fails closed.

## Technical Contract
- `OnTradeTransaction` is an evidence notification, not canonical state by itself.
- Only exact durable Request ↔ Order Ticket correlation can authorize Deal Association.
- Use exact 64-bit integer/string identifiers; never convert tickets/identifiers to double.
- Persist Deal Association before the Open Position Snapshot can use it to resolve an unresolved Request.
- Repeated event delivery must not duplicate volume or durable associations.
- Do not use Comment, approximate fill price, time proximity, or magic alone to infer the Request.
- If Tester event ordering is insufficient, use a bounded serialized History reconciliation path and document why.

## Approved CTO Design Contract — Exact Deal Evidence

### Event Intake
1. `OnTradeTransaction` handles relevant `TRADE_TRANSACTION_DEAL_ADD` notifications as a short callback. It captures the 64-bit Deal Ticket in a bounded pending queue (or bounded dirty-evidence set) and returns. It must not mutate Reducer state, append Deal Associations, create Position Mappings or run long History scans.
2. A serialized processor drains pending evidence from the EA event loop. It selects the exact Deal Ticket from History and reads `DEAL_ORDER`, `DEAL_ENTRY`, `DEAL_TYPE`, `DEAL_SYMBOL`, `DEAL_MAGIC`, `DEAL_POSITION_ID`, `DEAL_VOLUME` and `DEAL_PRICE`.
3. Correlation is permitted only when `DEAL_ORDER` exactly equals the Order Ticket persisted in the Execution Result of the one accepted unresolved Request. `CTrade.ResultDeal()` is a hint only; enumerate every History Deal whose `DEAL_ORDER` exactly matches that Order Ticket.
4. Validate the Deal is a supported entry/increasing-exposure deal, the Deal direction agrees with the Request, Symbol and Magic exactly match the Grid Instance, identifiers are nonzero and volume is positive. Unsupported entry semantics fail closed.
5. Process multiple partial Deals only if every Deal belongs to the same Position Identifier and aggregate volume does not exceed Requested Volume. A second Position Identifier or overfill is Recovery Error under the current one-Request-to-one-Position contract.
6. Persist complete evidence before WP-05C is allowed to reconcile the matching Open Position. Callback arrival or a `ResultDeal` value never creates Position Mapping by itself.

### Durable Deal Evidence Schema
The existing Reducer Deal Association projection is insufficient: it retains Request ID, Deal Ticket, Position Identifier and volume, omits Deal price/Order Ticket/Symbol/Magic/Entry Type, and rejects all duplicate Deal Tickets. Add a versioned Deal Association payload/projection retaining:
- Request ID and exact 64-bit Order Ticket;
- exact 64-bit Deal Ticket and Position Identifier;
- Symbol, Magic, Deal Entry type and Deal direction/type;
- Deal volume and actual Deal price.

Persist 64-bit identifiers without conversion to floating point; use the existing canonical ticket representation (decimal strings where JSON number precision would be unsafe). For an already-known Deal Ticket, compare all persisted evidence: exact same evidence is an idempotent no-op; any differing field is Recovery Error. Do not overwrite or double-count the Deal.

### Bounded History Recovery
- Trigger recovery when the callback is missed, the bounded queue overflows, or restart restores an accepted unresolved Request with a known Order Ticket.
- Select the History Order by its exact persisted Order Ticket and read its setup time. Run a bounded History selection interval from that setup time (with a documented safety margin) through current server time, then filter all returned Deals by exact `DEAL_ORDER`.
- The interval, queue capacity, retry count and per-cycle work limit must be explicit constants and covered by tests. Do not run an unbounded full-history scan every tick.
- A queue overflow must set an observable recovery-needed condition; never silently discard evidence.
- Failure to select the exact History Order, incomplete History selection or failure to read any required property is not proof of no fill. Keep the request unresolved and gate closed; after the bounded retry policy is exhausted, enter Recovery Error.
- After all exact-order Deals are persisted, acquire a complete/stable Open Positions snapshot and allow WP-05C to reconcile.

### Tester Proof Gate (D-06-02 remains open)
Before production event-bridge implementation is authorized, a separately approved Tester probe must capture actual transaction callbacks, callback ordering, exact History Order/Deal selection, Deal property availability, partial-fill behavior where supported, and restart recovery of an unresolved Request. The probe must use the exact supported Hedging Tester configuration and record terminal/build, symbol, execution/filling mode and tick model. This SPEC does not assert undocumented MT5 ordering guarantees. Unit Tests remain no-trade; only a separately approved Strategy Tester integration probe may send a Trade Request.

## Acceptance Criteria
- Each valid Entry Deal is associated with the exact Request and Position Identifier exactly once.
- Multiple partial Deals for one Position Identifier aggregate correctly within Requested Volume.
- Duplicate/out-of-order callbacks are idempotent.
- Invalid/incomplete/conflicting evidence creates no invalid durable association and keeps the gate closed.
- WP-05C can reconcile the matching complete/stable Position Snapshot and only then create Position Mapping / ACTIVE.
- Dedicated Fake History/Event tests and relevant no-trade Regression pass; CTO review APPROVED.
