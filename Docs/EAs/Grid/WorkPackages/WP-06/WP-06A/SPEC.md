# WP-06A — Production EA Bootstrap & Recovery Gate

สถานะ: CTO Design Draft — implementation not authorized

## Objective
Create the production Grid V1 EA shell and deterministic initialization/shutdown sequence that composes existing identity, lifecycle, persistence, reducer, restoration and WP-05C reconciliation components without creating duplicate state authority.

## Scope
- New production EA entry point under `Experts/TGK/` (exact filename to be finalized in task handoff).
- Chart Symbol only and Inputs: Mode, Upper Bound, Lower Bound, Grid Step, Fixed Lot.
- Validate inputs and Symbol constraints before any trade action.
- Initialize system-managed Grid Identity/Magic.
- Initialize/recover canonical Mapping Storage + Reducer and legacy Lifecycle persistence in an explicitly approved order.
- Restore runtime state and acquire/consume a complete/stable live Open Positions snapshot.
- Run WP-05C reconciliation and release Coordinator gate only on exact successful proof.
- Initialize required execution adapters/ports after identity and persistence are valid.
- Expose clear READY / WAIT_INITIAL_ENTRY / RECOVERY_ERROR / BLOCKED diagnostics.
- OnDeinit performs safe cleanup only; never delete committed trading state or close positions automatically.

## Out of Scope
- Sending Initial or Grid Entry requests.
- TP/SL management, Position closing, Mode/Step reset execution.
- General multi-Position mapping.
- Demo/Live validation.
- Changes to canonical Reducer schema unless an approved design amendment is raised.

## Dependencies
- Existing WP-05A/B/C source and tests.
- WP-06 architecture decision on config authority and initial bootstrap boundary.
- No implementation until WP-06B deal evidence contract and bootstrap dependencies are agreed.

## Allowed Files (proposed)
- New production EA source under `Experts/TGK/`.
- New EA bootstrap adapter only if required under `Include/BotTrade/Grid/`.
- Dedicated no-trade EA bootstrap tests under `Experts/TGK/Tests/Grids/`.
- WP-06A docs and project status.
- Existing core components are read-only unless a concrete approved defect is found and separately scoped.

## Technical Contract
- No Trade Request from OnInit, OnDeinit, or bootstrap path.
- A missing snapshot with owned live Positions is Recovery Error; never silently start a new Grid.
- Existing snapshot/replay failure, identity mismatch, config mismatch, unstable/invalid snapshot, orphan Position, or WP-05C failure keeps Entry/Candidate gate closed.
- Only a complete/stable Snapshot + exact Reducer Projection can release reconciliation gate.
- Every account scan is full-account then exact Symbol + Magic ownership filtering.
- No approximate price or comment mapping.
- Do not invent the configuration source of truth; resolve D-06-04 first.

## Acceptance Criteria
- Production EA compiles with 0 errors / 0 warnings in user MetaEditor.
- Fresh instance with no owned Position initializes to safe WAIT_INITIAL_ENTRY.
- Existing persisted instance restores canonical state and only opens gate after successful WP-05C reconciliation.
- Corrupt/missing/mismatched state with owned Positions fails closed.
- Foreign positions are not adopted or changed.
- Repeated OnInit/restart does not duplicate durable state or trade requests.
- OnDeinit never sends trade requests and does not erase persisted state.
- Dedicated no-trade tests and full Grid Regression pass; CTO review APPROVED.
