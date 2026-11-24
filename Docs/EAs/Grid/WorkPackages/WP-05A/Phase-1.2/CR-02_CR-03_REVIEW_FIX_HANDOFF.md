# WP-05A.2 — CR-02 / CR-03 Review-Fix Handoff

**Status:** Authorized for implementation by the Product Owner through this handoff request.
**Parent:** WP-05A.2 — Anchor State Transitions
**Review target:** `5206d1f9b8296162daa7b935e8398e6103f50466` (`CR-01 Review-Fix -- Fixed by Freebuff`)
**Branch:** `feature/grid-trading`
**Review result:** CHANGES REQUESTED — CR-02 (P1), CR-03 (P2)

## 1. Objective

Address the two findings from the CTO review of commit `5206d1f`:

- **CR-02 (P1):** Validate the Reducer's canonical Anchor state and mapping invariants before appending an `ANCHOR_STATE|READY` Journal record. An invalid/conflicting activation must not create a durable Journal mutation.
- **CR-03 (P2):** Add an end-to-end SELL activation test through the durable Adapter → Journal → Reducer path, complementing the existing Engine-only SELL crossing test and BUY durable Adapter test.

This is a narrow review-fix task. Do not expand WP-05A.2 scope.

## 2. CR-02 — Required behavior

Current implementation:

- `Include/BotTrade/Grid/GridEntryExecutionAdapter.mqh`
- Method: `RecordAnchorActivation(...)`
- It checks Adapter state, pending Coordinator activation and context, then calls `AppendAndApply()`.
- `AppendAndApply()` appends the Journal record before applying it to the Reducer.
- The Reducer currently validates `WAIT_ACTIVATION → READY` and rejects transitions when an Anchor Position Mapping exists.

This ordering permits an invalid activation to be appended before the Reducer rejects it. That violates the approved contract: invalid events must be rejected without Durable State mutation.

### Required implementation

Before any Journal append, validate the canonical Reducer state and mapping invariants:

1. Reducer is initialized, healthy and in the expected Grid context (retain existing context checks).
2. Canonical Anchor State is exactly `TGK_GRID_LEVEL_WAIT_ACTIVATION`.
3. No Anchor Position Mapping exists.
4. Coordinator has a pending activation and its context matches the same Grid configuration.
5. The transition being requested is exactly `WAIT_ACTIVATION → READY`.

Use existing query methods where appropriate (`TryGetAnchorState()`, `TryGetPositionMapping()`) or add the smallest suitable read-only validation API. Do not weaken or bypass Reducer validation. The Reducer remains the final authority when applying/replaying the event.

If pre-validation fails:

- Return failure.
- Do not call `port.AppendRecord()` / do not append any Journal record.
- Do not mutate Reducer state, Coordinator confirmation state or Journal sequence.
- Do not report success.
- Handle a detected Coordinator/Reducer disagreement conservatively; do not guess or silently synchronize states.

Only after pre-validation succeeds may the Adapter append the durable event and apply it through the canonical Reducer. Preserve the current append-before-in-memory-apply durability ordering. On append/flush failure, canonical Reducer state must remain `WAIT_ACTIVATION`, activation must remain pending, and recovery handling must remain fail-closed.

After successful durable append and Reducer application, confirm the Coordinator activation exactly once. Do not confirm before durable success.

### CR-02 tests required

Add focused fake-port tests proving that invalid activation attempts do not append:

- **Canonical state already READY:** Coordinator is pending but Reducer is READY; Adapter rejects and Journal append call count/sequence does not change.
- **Anchor mapping exists:** Coordinator is pending but Reducer has an Anchor Position Mapping; Adapter rejects and Journal append call count/sequence does not change.
- **Duplicate/conflicting transition:** A repeated or otherwise conflicting activation is rejected without a new Journal record. Cover the actual reachable API path; do not rely only on a guard that makes the test impossible to reach.
- **Valid transition control:** A valid WAIT_ACTIVATION + no mapping + pending Coordinator activation still appends exactly one event, moves Reducer to READY and confirms Coordinator once.
- Preserve the existing append-failure test: no canonical state mutation and pending activation remains available for recovery.

For every invalid-precondition test, assert at minimum:
- Adapter returns false.
- Fake port append count is unchanged.
- Reducer Anchor State is unchanged.
- Position Mapping count/state is unchanged.
- Journal sequence is unchanged.
- Coordinator activation remains pending (unless the specific conflict contract explicitly requires the Coordinator to enter a recovery state; document and test that behavior rather than silently clearing it).

Avoid adding a general-purpose event registry or unrelated idempotency mechanism.

## 3. CR-03 — SELL durable activation test

The current Engine test covers SELL downward crossing, but the Adapter durable path is tested only for BUY. Add a SELL case to:

`Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5`

Use fake ports only. No MT5 trade request.

The test must establish a SELL Grid context and a canonical Reducer fixture with:

- Anchor State = `WAIT_ACTIVATION`
- no Anchor Position Mapping
- matching instance, symbol, magic, mode and Config Epoch

Then verify:

1. SELL Coordinator reports a pending activation after the valid downward crossing.
2. `RecordAnchorActivation(..., TGK_GRID_MODE_SELL, ...)` succeeds.
3. Exactly one `ANCHOR_STATE|READY` lifecycle record is appended.
4. Reducer Anchor State becomes READY.
5. Coordinator pending activation is cleared only after durable success.
6. A second confirmation/activation attempt cannot append a duplicate event.

Keep the test symmetric with the existing BUY durable activation test where practical.

## 4. Scope boundaries

### Allowed

- Minimal changes to `GridEntryExecutionAdapter.mqh` and, only if necessary, a read-only Reducer validation API.
- Focused tests in `test_grid_entry_execution.mq5`; small supporting fixture changes in existing tests only if required.
- Update `IMPLEMENTATION_REPORT.md` with a distinct CR-02 / CR-03 review-fix subsection, preserving the existing CR-01 implementation history.
- Update relevant project status / testing documentation only where needed to accurately record the review-fix state.

### Explicitly prohibited

- No WP-05C Open Positions adapter, account scan, `PositionsTotal()`, or snapshot acquisition.
- No WP-05D production `OnTradeTransaction` integration.
- No MT5 Deal History lookup or close-reason classification.
- No changes to trading behavior, entry selection, activation direction, crossing rules, bounds, lot sizing or execution policy.
- No unrelated refactoring, formatting sweep or persistence redesign.
- No Trade Requests of any kind: no `OrderSend`, `CTrade`, `Buy()`, `Sell()`, `PositionClose()`, Demo or Live trading.
- No commit or push.

## 5. Required verification and report

Run focused tests and all applicable existing no-trade Grid Regression tests available in the development environment. Do not claim MetaEditor compile or MT5 test results unless actually run by the user.

The implementation report must include:

- CR-02 root cause and exact validation-before-append solution.
- CR-03 SELL durable-path test coverage.
- Files changed.
- Exact test names and results, distinguishing static checks from tests actually executed.
- Explicit confirmation that fake ports were used and no trade requests were sent.
- Any deviation or limitation.

Before finishing:

- Re-check `git status` and preserve all existing user changes.
- Do not reset, checkout, clean, stash, unstage, revert or overwrite existing work.
- Run `git diff --check` and `git diff --cached --check`.
- Review the complete staged and unstaged diffs; preserve the existing commit and do not amend it.
- Do not commit or push.
- Stop after implementation and report. Do not begin WP-05C.

## 6. Acceptance gate

Return the implementation report and exact changed-file list to the CTO for a fresh review.

WP-05A.2 remains **not Done** until:
1. CR-02 and CR-03 are implemented.
2. User runs MetaEditor Compile and the relevant no-trade Grid Regression tests and reports results.
3. CTO review is APPROVED.
4. WP-05A.2 is formally closed.

WP-05C remains blocked until WP-05A.2 is formally closed and separately authorized.
