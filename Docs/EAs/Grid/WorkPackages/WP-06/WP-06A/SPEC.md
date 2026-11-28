# WP-06A — Production EA Bootstrap & Recovery Gate

สถานะ: CTO Design — D-06-04 approved by Product Owner; implementation not authorized

## Objective
Create the production Grid V1 EA shell and deterministic initialization/shutdown sequence that composes existing identity, lifecycle, persistence, reducer, restoration and WP-05C reconciliation components without creating duplicate state authority.

## Scope
- New production EA entry point under `Experts/TGK/` (exact filename to be finalized in task handoff).
- Chart Symbol only and Inputs: Mode, Upper Bound, Lower Bound, Grid Step, Fixed Lot.
- Validate inputs and Symbol constraints before any trade action.
- Initialize system-managed Grid Identity/Magic.
- Initialize/recover canonical Mapping Storage + Reducer first; then initialize/restore Lifecycle orchestration metadata; finally validate every duplicated Lifecycle mirror against the canonical Reducer projection.
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
- Changes to canonical Reducer schema outside the approved D-06-04 Fixed Lot / schema-version migration amendment.

## Dependencies
- Existing WP-05A/B/C source and tests.
- D-06-04 canonical configuration authority and Fixed Lot schema/migration amendment (approved).
- WP-06B Deal Evidence interface contract; WP-06B runtime implementation may follow this interface, but A must not release entry gate until evidence/reconciliation dependencies are satisfied.
- D-06-03 Initial Bootstrap boundary (approved; implemented in WP-06C, not by WP-06A).
- No implementation until a fresh no-trade Grid Regression baseline PASS and explicit Product Owner implementation authorization.

## Allowed Files (proposed)
- New production EA source under `Experts/TGK/`.
- New EA bootstrap adapter only if required under `Include/BotTrade/Grid/`.
- Dedicated no-trade EA bootstrap tests under `Experts/TGK/Tests/Grids/`.
- WP-06A docs and project status.
- Existing core components are read-only unless a concrete approved defect is found and separately scoped.

## Initialization Order
1. Validate chart Symbol, all user Inputs and Symbol volume/tick constraints. No Trade Request is permitted.
2. Initialize system-managed Instance Identity and Magic for this chart instance.
3. Open/recover canonical Mapping Snapshot + Journal and replay the committed Reducer projection with schema/checksum/sequence validation.
4. If a legacy canonical schema lacks Fixed Lot, apply only the approved D-06-04 migration rule. If owned Positions or unresolved Requests exist, fail closed. Flush the migration record before continuing.
5. Initialize/restore Lifecycle orchestration metadata.
6. Compare every duplicated legacy Lifecycle field with the canonical Reducer projection. Any mismatch is Recovery Error; never silently repair.
7. Hydrate Runtime/Engine/Coordinator only from the canonical committed projection.
8. Initialize the bounded event-evidence intake/processor and execution ports only after identity and durable state are valid.
9. If an accepted unresolved Request exists, process queued evidence / exact-order History recovery and durably append all valid Deal Associations before reconciliation.
10. Acquire a complete/stable full-account Open Positions snapshot; filter exact Symbol + Magic ownership and run WP-05C reconciliation.
11. Release the new-entry gate only after exact successful reconciliation. A genuinely fresh empty instance enters `WAIT_INITIAL_ENTRY`; otherwise expose the precise BLOCKED/RECOVERY_ERROR reason.

## Technical Contract
- No Trade Request from OnInit, OnDeinit, or bootstrap path.
- A missing snapshot with owned live Positions is Recovery Error; never silently start a new Grid.
- Existing snapshot/replay failure, identity mismatch, config mismatch, unstable/invalid snapshot, orphan Position, or WP-05C failure keeps Entry/Candidate gate closed.
- Only a complete/stable Snapshot + exact Reducer Projection can release reconciliation gate.
- Every account scan is full-account then exact Symbol + Magic ownership filtering.
- No approximate price or comment mapping.
- Apply the D-06-04 authority split and explicit legacy mirror validation described below; any unresolved schema/migration mismatch keeps the gate closed.

## Configuration Authority & Migration Contract — D-06-04 Approved

Canonical Mapping Reducer Snapshot + Journal is the sole authority for trading configuration and geometry: Instance/Symbol/Magic, Mode, Bounds, Grid Step, Anchor, level geometry/count, Config Epoch, Level states, Deal Associations and Position Mappings. Extend the canonical persisted configuration schema to include Fixed Lot because it controls future execution sizing.

Lifecycle Persistence owns orchestration metadata only: lifecycle state, reset reason, pending requested Mode/Step/Magic and transition bookkeeping. Its duplicate Mode/Step/Anchor/Level Count values are legacy mirrors/checksums, never a second authority. During restore, compare every overlapping field against the canonical Reducer projection; any mismatch is Recovery Error. Do not select a winner or silently repair either store.

Config Epoch advances only through a canonical committed configuration transition. Runtime, Engine and Coordinator hydrate from the committed projection. Changed Inputs are requests to Lifecycle/reset orchestration; canonical trading config does not change until old Positions are closed and the canonical reset commit succeeds.

### Legacy Schema Migration
- Bump/version the canonical configuration and snapshot/journal schema explicitly. Preserve existing committed Level, Deal Association and Position Mapping history during migration; never discard/recreate it as a shortcut.
- If a legacy snapshot has no canonical Fixed Lot, migration may adopt the currently validated Fixed Lot Input only when there is no owned live Position and no unresolved Entry Request. Record the adopted value in a durable schema-migration/configuration commit before releasing the entry gate; advance Config Epoch according to the canonical transition rule and emit a diagnostic that identifies the adopted Input value.
- If any owned Position or unresolved Request exists, do not infer the historical Fixed Lot from Lifecycle or current Inputs. Keep the gate closed with Recovery Error and require a separately reviewed recovery procedure.
- If Lifecycle mirrors disagree with the canonical legacy values, migration does not resolve the conflict by precedence. Fail closed.
- Migration must be idempotent across restart: once the migration record is durable, replay restores the same Fixed Lot and does not apply the migration twice.
- Unit tests must cover valid empty-instance migration, active-position block, unresolved-request block, mirror mismatch, append/flush failure and restart after durable migration.

## Acceptance Criteria
- Production EA compiles with 0 errors / 0 warnings in user MetaEditor.
- Fresh instance with no owned Position initializes to safe WAIT_INITIAL_ENTRY.
- Existing persisted instance restores canonical state and only opens gate after successful WP-05C reconciliation.
- Corrupt/missing/mismatched state with owned Positions fails closed.
- Foreign positions are not adopted or changed.
- Repeated OnInit/restart does not duplicate durable state or trade requests.
- OnDeinit never sends trade requests and does not erase persisted state.
- Dedicated no-trade tests and full Grid Regression pass; CTO review APPROVED.
