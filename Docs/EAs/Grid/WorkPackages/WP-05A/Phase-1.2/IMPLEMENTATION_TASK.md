# Freebuff Implementation Task — WP-05A.2

**Authorization:** Product Owner approved SPEC and TEST_PLAN on 2026-11-23.  
**Execution status:** READY FOR IMPLEMENTATION HANDOFF, but **DO NOT START SOURCE CHANGES until the user reports the pre-change Grid Regression Baseline for this WP**.  
**Developer:** Freebuff  
**CTO:** ChatGPT  
**QA / MetaEditor verification:** User

## Required reading

1. Repository `AGENTS.md` (mandatory).
2. `SPEC.md` in this directory.
3. `TEST_PLAN.md` in this directory.
4. `Docs/EAs/Grid/WorkPackages/WP-05A/README.md`.
5. Relevant source and tests identified in the SPEC; inspect current HEAD and working tree before editing.

Freebuff works directly with the repository. Do not use Serena MCP.

## Authorized scope

Implement WP-05A.2 exactly as approved in SPEC and TEST_PLAN:

- Anchor Position Mapping confirmation activates durable Anchor State.
- Partial Close updates remaining Volume / refreshed Position Ticket and keeps Anchor/Level ACTIVE.
- Full Close is a reason-free reducer transition keyed by the mapped Position Identifier; atomically remove mapping and set the matching Anchor/Level state to READY or WAIT_ACTIVATION.
- Consolidate WAIT_RETURN into READY for new state writes; preserve legacy enum numeric slot and WAIT_ACTIVATION ordinal; normalize legacy values during replay/load.
- Preserve V1 entry records and legacy close record replay compatibility as specified.
- Implement state-based idempotency; do not add a processed close-deal registry.
- Validate reducer preconditions before mutation; fail closed on invalid/conflicting evidence.
- Add all applicable tests from TEST_PLAN, including replay, snapshot, crash/failure and regression tests.

## Explicit prohibitions

- Do not implement MT5 Open Positions scanning or the production reconciliation adapter; that belongs to WP-05C.
- Do not add Closing Deal History lookup, TP/SL/manual close classification, closing price, or Closing Deal Ticket identity.
- Do not change Grid entry selection, crossing direction, Bounds, lot sizing, reset behavior or unrelated trading behavior.
- Do not implement production OnTradeTransaction integration; that belongs to WP-05D.
- No CTrade / OrderSend / PositionClose calls from tests. No Demo or Live trade requests.
- No commit, push, reset, checkout, clean, stash, or destructive operation.
- Preserve all pre-existing user changes. Do not overwrite or revert unrelated work.

## Implementation expectations

- Follow existing MQL5 style: 2-space indentation; multiline parameters one per line with minimal indentation.
- Prefer small, focused changes and existing architecture; do not introduce a second persistence authority.
- Inspect all call sites and serialized contracts before changing payloads/enums.
- If an approved requirement is technically impossible or conflicts with existing durable data, stop and report the exact blocker; do not silently alter the contract.
- Do not broaden scope without CTO/Product Owner approval.

## Deliverables

1. Source and test changes within authorized scope.
2. `IMPLEMENTATION_REPORT.md` in this directory:
   - files changed and design decisions;
   - SPEC acceptance criteria mapped to implementation;
   - TEST_PLAN cases implemented and exact results;
   - compatibility behavior for legacy records and snapshots;
   - known limitations and any deviations (none assumed);
   - explicit statement that no trade requests were sent.
3. Update relevant WP docs only as required by the approved task; do not claim user Compile/Runtime PASS.
4. Stop after implementation and report completion. Do not begin WP-05C or any next phase.

## Completion handoff

After Freebuff reports implementation:
- User compiles and runs the required no-trade tests in MetaEditor and reports exact results.
- CTO performs formal code review only after user reports Compile/Test PASS.
- Any review fixes require a separate explicit handoff.
- WP-05A.2 is not Done until user verification, CTO APPROVED, documentation consistency gate, and user confirmation.
