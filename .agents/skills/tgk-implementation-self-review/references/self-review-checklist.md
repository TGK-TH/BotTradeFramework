# TGK Implementer Self-Review Checklist

Load this checklist for changes involving runtime state, state machines, persistence, event processing, reconciliation, or failure recovery. For simpler tasks, use only the relevant sections.

## Contract and scope

- [ ] Every changed behavior maps to an approved SPEC requirement or an explicitly authorized CTO finding.
- [ ] Changed files are within the active Card's allowed scope.
- [ ] No product/trading behavior, public contract, persistence format, or authorization boundary changed silently.
- [ ] Existing callers, consumers, and compatibility paths were inspected where relevant.

## Control flow and invariants

- [ ] The complete production path is traced: event/input → validation → mutation → persistence → externally visible result.
- [ ] Validation occurs before irreversible side effects or durable append when the contract requires rejection without mutation.
- [ ] Reducers/authoritative state owners remain the final authority; adapters/coordinators do not bypass canonical validation.
- [ ] Tests use legal, reachable fixtures and demonstrate that execution reaches the intended invariant/guard.
- [ ] A test does not claim to prove a later guard when an earlier lookup or validation rejects first.
- [ ] BUY and SELL behavior is covered where direction or executable quote side differs.
- [ ] Boundary and equality cases are tested where they affect state transitions.

## Durability, idempotency, and recovery

- [ ] Related durable changes are atomic when the contract requires one logical transition.
- [ ] Append/apply ordering is correct; append failure cannot leave memory ahead of durable state.
- [ ] Invalid or conflicting evidence fails closed and does not partially mutate durable or runtime state.
- [ ] Duplicate/replayed events are idempotent according to the approved identity and canonical state model.
- [ ] Restart, snapshot, journal replay, and rotation behavior remain coherent when affected.
- [ ] Hydration uses canonical persisted identity/configuration as the source of truth; caller input is validated, not silently promoted to authority.
- [ ] Successful-then-failed initialization/hydration cannot expose stale state through fields or accessors.
- [ ] Pending/unresolved requests preserve the exact evidence required by the contract without being promoted to confirmed/active state.
- [ ] Reconciliation or safety gates cannot be bypassed by alternate entry points or implicit side effects.

## Test quality

- [ ] Each test has a clear Arrange/Act/Assert structure and a named invariant.
- [ ] Negative tests prove the intended rejection reason/path, not merely any failure.
- [ ] Duplicate, retry, partial-progress, failure-injection, and recovery cases are included where applicable.
- [ ] Tests assert both the result and the absence of forbidden side effects/state changes.
- [ ] Unit tests do not send Trade Requests or touch non-test account positions.
- [ ] Test names, comments, and reports accurately describe what the fixture reaches and proves.

## Compile and evidence

- [ ] Every affected MQL5 program was compiled using the current `AGENTS.md` procedure, or the exact blocker is documented.
- [ ] Every affected compile reports 0 errors and 0 warnings; warnings were fixed rather than waived.
- [ ] Changed `.mqh` includes were traced to all affected `.mq5` consumers and each consumer was compiled.
- [ ] Compile evidence identifies exact program paths, result lines, and log location.
- [ ] Compile evidence is separate from MT5 test evidence.
- [ ] MT5 test suites were not run by the Implementer when reserved for the Product Owner.

## Final diff and handoff

- [ ] Full diff reviewed, not only edited hunks.
- [ ] `git diff --check` passes.
- [ ] Working-tree status reviewed; pre-existing user changes preserved.
- [ ] Implementation report maps requirements/findings to files and evidence.
- [ ] Unverified behavior, unavailable tests, limitations, and open questions are explicit.
- [ ] No commit or push was made unless explicitly authorized.
