# WP-06D — Position Management, TP & Configuration Reset

สถานะ: CTO Design Draft — TP rule recovered from prior Product Owner decision; technical integration contract still requires CTO review before implementation

## Objective
Integrate safe management of existing Grid-owned Positions, the approved TP behavior, and Mode/GridStep reset lifecycle so the EA continues managing existing exposure even when new entries are blocked.

## Scope
- Apply broker-side per-Position TP: BUY = actual Entry Fill Price + 1 × GridStep; SELL = actual Entry Fill Price − 1 × GridStep; no Basket TP.
- Same TP rule applies to Anchor and normal Positions. Do not recalculate/modify TP of an already-open Position when GridStep input changes; new Positions use current GridStep.
- After TP, wait for price to retouch/cross the original Entry Level before re-entry; prove this using the reason-free Full Close + Level/quote state contract.
- Define safe initial TP placement and retry behavior. Document how the system avoids silently leaving a newly opened Position without its required broker-side TP.
- Ensure management uses exact owned Position Identifier/current Ticket and Symbol + Magic validation.
- Integrate current reset/close Runtime path: call close adapter only on CLOSE_REQUIRED, then obtain a fresh complete/stable snapshot and reconcile before rebuilding.
- Mode change and GridStep change follow approved Close → Reconcile → Rebuild/Wait Initial Fill sequence.
- Bounds outside market blocks new entries only; TP/management and reset safety continue.
- Partial Close retains ACTIVE; Full Close is recognized only by WP-05C complete/stable snapshot absence and uses reason-free canonical transition.
- No close-reason inference or Closing Deal History is introduced unless Product Owner separately changes the contract.

## Out of Scope
- General multi-Position-per-Request support.
- Demo/Live trading validation.
- Any new TP/SL rule inferred from old documents or code comments.
- Manual/foreign Position management.

## Dependencies
- WP-06A through WP-06C.
- Previously approved Product Owner TP contract recorded in D-06-01.
- WP-05C stable snapshot/reconciliation contract; no TP/Non-TP close classification.

## Acceptance Criteria
- Broker-side per-Position TP is set to actual fill ± one GridStep for BUY/SELL respectively, including Anchor.
- Existing Position TP is not modified by GridStep input changes; new Positions use the current Step.
- TP closure leads to READY/WAIT_ACTIVATION such that re-entry cannot occur until original Entry Level is retouched/crossed, without reason inference.
- Only Grid-owned Positions are modified/closed.
- TP management failure does not silently mark a Position closed or clear mapping.
- Partial/full close state follows current canonical WP-05A.2/WP-05C behavior.
- Mode/Step reset cannot rebuild until fresh reconciliation confirms owned Position count/mappings are clear.
- Existing Position management continues while outside Bounds.
- Unit tests use fake trade/position ports and send no Trade Requests; user-authorized Strategy Tester integration scenarios validate execution.
- CTO review APPROVED.
