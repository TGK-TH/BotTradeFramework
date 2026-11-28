# WP-06 — Grid V1 Production EA / Strategy Tester Integration

อัปเดต: 2026-11-28
สถานะ: CTO Design & Planning — ยังไม่อนุมัติ Implementation

## เป้าหมาย
เชื่อม Grid components ที่ผ่าน Unit/Component Tests แล้วให้เป็น Production Grid V1 EA ซึ่งทำงานได้จริงและตรวจสอบได้ใน MT5 Strategy Tester โดยคง Current Contract หนึ่ง Entry Request ต่อหนึ่ง Position Identifier สำหรับ execution configuration ที่พิสูจน์แล้วว่าปลอดภัย

## ลำดับ Milestone
1. WP-06A — Production EA Bootstrap & Recovery Gate
2. WP-06B — Trade Event Intake & Entry Deal Correlation
3. WP-06C — Initial Anchor & Grid Entry Runtime
4. WP-06D — Position Management, TP & Configuration Reset
5. WP-06E — Strategy Tester End-to-End Readiness

WP-06A ถึง WP-06E เป็น Dependency chain ตามลำดับ แต่ Design/Planning ของหลาย WP ทำคู่ขนานได้ตาม workflow. Implementation / User Verification / CTO Review ทำทีละ WP เท่านั้น.

## Current Source Findings
- Grid components exist for Identity, Lifecycle, Runtime Orchestration, Level Engine/Coordinator, Entry Policy/Resolver/Adapter/Pipeline, Mapping Reducer/Snapshot Storage, Runtime Restoration, and Open Positions Reconciliation.
- No production Grid V1 EA shell or production Grid EA event loop exists under `Experts/TGK`.
- No `OnTradeTransaction` handler or production deal-history correlation bridge was found in current EA sources.
- WP-05C consumes durable Deal Association evidence when validating unresolved Entry evidence; it does not itself discover Entry Deals or create those Deal Association records.
- `CTGKGridLevelRuntimeCoordinator::UpdatePrice()` selects a candidate; `Reconcile()` accepts Position/Close facts and updates candidate state; `CTGKGridEntryExecutionPipeline` connects Candidate → Resolver/Policy/Adapter.
- Initial Anchor has a distinct bootstrap requirement: the first fill establishes Anchor price, after which Engine/Coordinator geometry and canonical persisted configuration can be built.
- Existing `CTGKGridOrderExecutionAdapter` is currently a close/reset adapter, not a general TP management subsystem.
- Current Strategy Tester execution model and its exact Order/Deal/Position evidence must be verified; do not assume one Position per Entry Request without testing.

## Design Boundaries
- Chart Symbol only; no user Symbol input.
- Inputs: Upper Bound, Lower Bound, BUY/SELL Grid Mode, Grid Step, Fixed Lot. Identity/Magic are system-managed.
- Initial Entry only while executable-side price is within Bounds.
- Initial Anchor = actual fill price, never request price or estimated price.
- Outside Bounds blocks new entries only; existing Position management continues.
- One Candidate per price check; existing BUY/SELL candidate selection and hard-bound behavior remain unchanged.
- Accepted CTrade result is not a fill. No Position Mapping / ACTIVE transition without durable Deal Association + authoritative Position evidence.
- Foreign/Manual/other-instance positions must never be adopted or modified.
- Unit tests must not send Trade Requests. Strategy Tester trade tests require explicit Product Owner authorization and dedicated test configuration.
- No Demo/Live execution in this milestone.
- No multi-Position-per-Request architecture unless Strategy Tester evidence demonstrates the current contract is unsafe or insufficient. If encountered, stop and raise a design decision.

## TP Contract (previously approved by Product Owner)
- TP is per Position, not Basket TP.
- BUY TP = that Position's actual Entry Fill Price + 1 × GridStep.
- SELL TP = that Position's actual Entry Fill Price − 1 × GridStep.
- TP is broker-side / Position-level and applies to Anchor and normal Grid Positions.
- After TP, re-entry waits until price retouches/crosses the original Entry Level; do not reopen immediately.
- Existing Positions retain their already-set TP if GridStep input changes; new Positions use the new Step. The approved GridStep reset still closes old Positions before rebuilding.
- WP-05A.2 Full Close remains reason-free. TP recycle behavior must be achieved through the Level/quote state contract, not Closing Deal History or TP/Non-TP classification. WP-06D must verify this equivalence.

## CTO Design Review Findings (2026-11-27)

Product Owner approved D-06-03 (typed Initial Entry Intent + atomic Initial Bootstrap schema amendment) and D-06-04 (canonical Reducer configuration authority + Fixed Lot persistence/migration) on 2026-11-27. These are design approvals only; implementation remains unauthorized.
- WP-06B recommended event model: OnTradeTransaction is a short notification/enqueue path; serialized processing resolves exact Deal Ticket and exact DEAL_ORDER against the durable Order Ticket. A bounded exact-order History fallback is required for missed callbacks, queue overflow and restart. D-06-02 is now closed based on the R-03 Tester trace; true terminal restart remains a separate D-06-06 item.
- WP-06C requires a distinct Initial Entry Intent and one atomic Initial Bootstrap journal commit. The current normal Entry Pipeline cannot start a fresh Grid because it requires an existing Config Epoch/geometry. This requires a scoped Reducer/Journal schema amendment.
- WP-06B also requires a versioned Deal evidence projection: current Reducer records omit Deal price and reject all duplicate Deal Tickets, so weighted Anchor recovery and exact duplicate idempotency cannot be achieved by the existing schema unchanged.
- WP-06A recommended authority split: canonical Mapping Reducer Snapshot/Journal owns trading configuration and geometry; extend it to persist Fixed Lot. Lifecycle Persistence owns orchestration/reset metadata; duplicated legacy values are mirrors and must match or fail closed.
- These are CTO design recommendations, not implementation authorization. See WP-06_DECISIONS.md and each child SPEC for details and required approvals.

## Work Package Index
- [WP-06A SPEC](WP-06A/SPEC.md) · [TEST_PLAN](WP-06A/TEST_PLAN.md)
- [WP-06B SPEC](WP-06B/SPEC.md) · [TEST_PLAN](WP-06B/TEST_PLAN.md)
- [WP-06C SPEC](WP-06C/SPEC.md) · [TEST_PLAN](WP-06C/TEST_PLAN.md)
- [WP-06D SPEC](WP-06D/SPEC.md) · [TEST_PLAN](WP-06D/TEST_PLAN.md)
- [WP-06E SPEC](WP-06E/SPEC.md) · [TEST_PLAN](WP-06E/TEST_PLAN.md)

## D-06-02 Minimal Strategy Tester Probe — CLOSED
Product Owner accepted D-06-02 on 2026-11-28 after R-03 runtime evidence and CTO review. The minimal BUY path passed for one Tester request: persisted request/order evidence, exact History Deal set, Position Identifier correlation, callback capture, and same-run recovery. See [Probe SPEC](D-06-02_PROBE/SPEC.md), [TEST_PLAN](D-06-02_PROBE/TEST_PLAN.md), [IMPLEMENTATION_REPORT](D-06-02_PROBE/IMPLEMENTATION_REPORT.md), and [Trello card #24](https://trello.com/c/7S8Pw7nE/24-d-06-02-minimal-strategy-tester-probe).

**Limitations retained:** `TRUE_RESTART_RECOVERY=NOT_TESTED`; same-run recovery is not a true EA/Terminal restart. R-03 exercised BUY only and one Deal; it does not prove SELL symmetry or partial-fill/multi-Deal behavior. `FileFlush()` invocation does not prove OS/hardware crash durability. These gaps are not silently treated as PASS.

True EA/Terminal Restart Recovery is tracked separately by [D-06-06 — Trello card #25](https://trello.com/c/2ga9zY56/25-d-06-06-true-ea-terminal-restart-recovery-proof). D-06-06 is currently design/planning only; implementation and any Trade Request remain unauthorized. Keep its validation focused on the minimum essential restart and process-crash recovery evidence needed for Grid V1. Strategy Tester same-run recovery must not be used as a substitute for a genuine terminal process restart.

## Completion Rule
Each WP requires approved SPEC/TEST_PLAN, a fresh pre-change no-trade Grid Regression baseline, explicit Product Owner implementation authorization, Implementer report, user MetaEditor/MT5 verification, CTO review, and documentation consistency checks. Completion of WP-06E means the EA is ready for the agreed Strategy Tester validation milestone; it does not mean profitable or Demo-ready.
