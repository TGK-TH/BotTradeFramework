# Implementation Task — WP-05A.3

**Task:** WP-05A.3 — Anchor State Persistence Integration & Hardening  
**Task status:** HANDOFF READY — awaiting explicit Product Owner implementation authorization  
**Design/Scope:** Product Owner approved 2026-11-25  
**Pre-change baseline:** User reported on 2026-11-25 that the current test run passed. This satisfies the reported baseline gate for handoff preparation. Per-file logs/results were not attached to this task document; do not invent or independently claim those details.  
**Implementer:** Codex or Freebuff, selected exclusively by the Product Owner  
**CTO / Reviewer:** ChatGPT  
**Product Owner / Runtime QA:** User

## 1. Required Reading

1. Repository root AGENTS.md.
2. This directory's SPEC.md.
3. This directory's TEST_PLAN.md.
4. Docs/EAs/Grid/WorkPackages/WP-05A/README.md.
5. Inspect the current source and test files listed below before editing.
6. Inspect current Git branch/status/diff and preserve all pre-existing user work.

The repository documents are the complete task contract. Do not depend on prior chat history, model memory, or Serena memories. Do not install or use Serena MCP.

## 2. Authorization Boundary

This file prepares the implementation handoff only. **Do not modify source or tests until the Product Owner explicitly authorizes implementation of WP-05A.3.**

The approved Design/Scope and the reported pre-change baseline do not, by themselves, authorize source changes. The Product Owner will choose and invoke either Codex or Freebuff. Do not select or switch the Implementer.

Once explicitly authorized, implement only this Card. Do not start WP-05B or WP-05C.

## 3. Objective

Prove that non-default Anchor States survive the canonical persistence path without losing or contradicting Anchor Position Mapping across Snapshot serialization, Journal append/replay, Snapshot rotation, and restart recovery.

This is persistence verification/hardening only. It must not add trading behavior or MT5 account integration.

## 4. Authorized Implementation Scope

Implement the approved scenarios and Acceptance Criteria in SPEC.md and TEST_PLAN.md:

- READY with no Anchor Position Mapping.
- ACTIVE with exactly one valid Anchor Position Mapping.
- WAIT_ACTIVATION after reason-free Full Close with no Anchor Mapping.
- Reducer ExportSnapshot() through Snapshot Storage Bootstrap()/Append()/Rotate(), storage restart Initialize()/Replay(), and Reducer RestoreSnapshot()/Replay().
- Anchor State and Mapping invariants before/after rotation and restart.
- Journal checkpoint and sequence continuity for Anchor lifecycle records.
- Relevant pre-commit and post-commit rotation failure/recovery behavior.
- Invalid/missing/conflicting Anchor State or Mapping must fail closed as specified.

Production code may be changed **only** when a new test demonstrates a concrete, reproducible defect within this approved persistence contract. If a defect requires a contract change, broader scope, migration, or behavior decision, stop and report it; do not silently redesign.

## 5. Allowed Files

Inspect these files as needed. Modify only the following files unless the CTO/Product Owner approves a specific scope adjustment:

### Primary test target
- Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5

### Conditional test target
- Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5 — only if a focused reducer regression is necessary.

### Conditional production targets
- Include/BotTrade/Grid/GridEntryMappingReducer.mqh
- Include/BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh

Production targets are permitted only for a reproducible defect exposed by this task's tests. Do not edit GridPersistence.mqh to create a second persistence authority.

### Required task output
- Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.3/IMPLEMENTATION_REPORT.md

Do not modify other source files, unrelated tests, architecture contracts, WP-05B/WP-05C files, or product behavior.

## 6. Technical Invariants and Prohibitions

- CTGKGridEntryMappingReducer remains the canonical Trading State Authority.
- CTGKGridEntryMappingSnapshotStorage remains the owner of Snapshot/Journal/Manifest persistence and rotation.
- Do not introduce a second Anchor State persistence authority.
- ACTIVE requires exactly one valid Anchor Position Mapping; READY and WAIT_ACTIVATION require no Anchor Mapping.
- Full Close remains a reason-free atomic transition under WP-05A.2.
- Preserve the existing Snapshot/Journal generation commit-point semantics; never mix generations.
- Schema remains V1. Do not add migration or backward compatibility for old V1 snapshots missing the now-required Anchor State.
- Do not change the WP-05A.2 State Transition Contract.
- No MT5 Open Positions scan, Reconciliation Adapter, Closing Deal History, TP/NON_TP, Close Reason, OnTradeTransaction, production EA handler, order execution, or Demo/Live trading.
- Tests must use deterministic fake records and a dedicated test storage namespace.
- Never clean up storage belonging to a real Instance or user data.
- No CTrade, OrderSend, PositionClose, or any Trade Request from tests.
- No commit, push, reset, checkout, clean, stash, or destructive Git operation.
- Preserve all pre-existing staged, unstaged, and untracked changes.

## 7. Test Requirements

Implement all applicable cases A3-01 through A3-09 from TEST_PLAN.md. Keep assertions for:

- Anchor State before/after every persistence boundary.
- Anchor Mapping count and Position Identifier.
- Position Ticket, Remaining Volume, and Target.
- Reducer Recovery Status.
- Snapshot Checkpoint, Last Sequence, and Next Sequence.
- Active Manifest / Snapshot / Journal Generation.
- Storage files and cleanup behavior.
- Preservation of the previous valid generation when pre-commit fails.

Do not weaken existing assertions to make a test pass. If an expected result conflicts with the approved contract, stop and report the conflict.

## 8. Compile and Runtime Verification

- Compile every affected MQL5 test program and every program affected by a changed .mqh include using the verified MetaEditor environment when it is accessible.
- Resolve all compile errors and warnings; target 0 errors, 0 warnings.
- If the compile environment is inaccessible, report that explicitly with the exact limitation/log evidence. Do not infer compile success from static checks.
- The Implementer must not claim MT5 runtime Test PASS. The Product Owner runs the specified test EAs and the full latest no-trade Grid Regression suite, then reports actual results.
- Compile evidence and user runtime-test evidence must be recorded separately.
- No Demo trade-request test is part of this Card.

## 9. Implementation Report

Create IMPLEMENTATION_REPORT.md and include:

1. Implementer identity (Codex or Freebuff) and completion date.
2. Changed files and why each change was necessary.
3. Mapping of each SPEC Acceptance Criterion to implementation/test evidence.
4. A3-01…A3-09: implemented, compiled, and any case not applicable (with rationale).
5. Exact MetaEditor compile results/log locations for every affected program, or the precise reason compile was unavailable.
6. Tests not run by the Implementer (runtime tests are reserved for the Product Owner).
7. Explicit statement confirming no Trade Requests were sent and no real Instance/user storage was touched.
8. Any deviations, unresolved issues, or risks. Do not claim zero deviations unless verified.

## 10. Stop Condition and Next Step

After implementation and compile reporting, stop. Do not begin WP-05B, WP-05C, or another Card.

The Product Owner then runs the WP-05A.3 test plan and latest no-trade Grid Regression suite. ChatGPT begins formal Code Review only after the Product Owner reports runtime Test PASS. Any review fixes require a separate scoped handoff and a fresh user Compile/Test cycle.

WP-05B implementation remains blocked until WP-05A.3 is user-verified, CTO Code Review is APPROVED, documentation is consistent, and the Product Owner confirms closure.
