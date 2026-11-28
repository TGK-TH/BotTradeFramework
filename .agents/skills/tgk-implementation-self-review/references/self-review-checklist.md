# TGK Implementer Self-Review Checklist

Load this checklist for changes involving runtime state, state machines, persistence, event processing, reconciliation, or failure recovery. For simpler tasks, use only relevant sections. Every remediation after a CTO Review Reject must additionally complete the full protocol in references/adversarial-review-protocol.md.

## Contract and scope

- [ ] Every changed behavior maps to an approved SPEC requirement or explicitly authorized CTO finding.
- [ ] Changed files are within the active Card's allowed scope.
- [ ] No product/trading behavior, public contract, persistence format, or authorization boundary changed silently.
- [ ] Existing callers, consumers, and compatibility paths were inspected where relevant.
- [ ] Every acceptance criterion has a stated observable pass condition and evidence source.

## Control flow and invariants

- [ ] The complete path is traced: event/input → validation → mutation → persistence → externally visible result.
- [ ] Validation occurs before irreversible side effects or durable append when required.
- [ ] Reducers/authoritative state owners remain the final authority; adapters/coordinators do not bypass canonical validation.
- [ ] Tests use legal, reachable fixtures and demonstrate execution reaches the intended invariant/guard.
- [ ] A test does not claim to prove a later guard when an earlier lookup or validation rejects first.
- [ ] BUY and SELL behavior is covered where direction or executable quote side differs.
- [ ] Boundary and equality cases are tested where they affect state transitions.
- [ ] All callers and alternate entry points preserve the same safety and failure guarantees.

## API and language semantics

- [ ] For every consequential API call, the exact signature and return type were checked against authoritative MQL5/platform documentation or verified declarations.
- [ ] Return values are interpreted according to the documented success convention; nonzero/zero is not assumed to mean success without evidence.
- [ ] Void-returning operations are not treated as if they expose a success result.
- [ ] GetLastError() is used only where the API contract supports it; its lifecycle/reset behavior and the immediately preceding operation are understood.
- [ ] Numeric parsing/conversion checks the complete input, malformed suffixes, sign/range, overflow, precision, and finite values as applicable.
- [ ] Array indices, enumeration bounds, buffer capacities, and zero/invalid identifiers are handled explicitly.
- [ ] A failed property read or incomplete enumeration cannot be silently converted into valid/empty evidence.
- [ ] Error paths distinguish NOT_FOUND, invalid/corrupt data, and genuine I/O/API failure where the contract requires it.

## Durability, idempotency, and recovery

- [ ] Related durable changes are atomic when the contract requires one logical transition.
- [ ] Append/apply ordering is correct; append failure cannot leave memory ahead of durable state.
- [ ] Invalid or conflicting evidence fails closed and does not partially mutate durable or runtime state.
- [ ] Duplicate/replayed events are idempotent according to approved identity and canonical state model.
- [ ] Restart, snapshot, journal replay, and rotation behavior remain coherent when affected.
- [ ] Hydration uses canonical persisted identity/configuration as source of truth; caller input is validated, not silently promoted to authority.
- [ ] Successful-then-failed initialization/hydration cannot expose stale state through fields or accessors.
- [ ] Pending/unresolved requests preserve exact evidence required by contract without being promoted to confirmed/active state.
- [ ] Reconciliation or safety gates cannot be bypassed by alternate entry points or implicit side effects.
- [ ] Partial writes, flush limitations, interrupted persistence, and post-side-effect evidence loss are explicitly handled.

## Test quality and adversarial checks

- [ ] Each test has clear Arrange/Act/Assert structure and a named invariant.
- [ ] Negative tests prove the intended rejection reason/path, not merely any failure.
- [ ] Duplicate, retry, partial-progress, failure-injection, and recovery cases are included where applicable.
- [ ] Tests assert both the result and absence of forbidden side effects/state changes.
- [ ] Unit tests do not send Trade Requests or touch non-test account positions.
- [ ] Test names, comments, and reports accurately describe what the fixture reaches and proves.
- [ ] Ask: "What incomplete, stale, malformed, contradictory, or partially available input could still make this code return success or PASS?"
- [ ] Challenge the happy path with zero tickets/IDs, missing properties, partial enumeration, buffer overflow, stale state, malformed persisted records, and API failure where relevant.
- [ ] Confirm that a failed/incomplete data source cannot be interpreted as authoritative absence.

## Acceptance evidence

- [ ] Every AC has a requirement-to-code/test mapping.
- [ ] Every claimed PASS is supported by positive evidence for the exact condition, not merely by a function call, request submission, nonzero value, or absence of an error.
- [ ] Evidence is tied to the exact record/entity/session under test; no arbitrary first array element is used as a proxy for validated evidence.
- [ ] Required snapshots are complete and all required properties are valid before drawing conclusions from them.
- [ ] A missing or incomplete evidence source produces NOT_TESTED/INCOMPLETE/ERROR as specified, never a false PASS.
- [ ] The report distinguishes implementation evidence from test execution evidence and identifies who produced each.

## Compile and evidence

- [ ] Every affected MQL5 program was compiled using current AGENTS.md procedure, or exact blocker is documented.
- [ ] Every affected compile reports 0 errors and 0 warnings; warnings were fixed rather than waived.
- [ ] Changed .mqh includes were traced to all affected .mq5 consumers and each consumer was compiled.
- [ ] Compile evidence identifies exact program paths, result lines, and log location.
- [ ] Compile evidence is separate from MT5 test evidence.
- [ ] MT5 test suites were not run by Implementer when reserved for Product Owner.
- [ ] Compile PASS is not presented as proof of runtime correctness or CTO approval.

## Final diff and handoff

- [ ] Full diff reviewed, not only edited hunks.
- [ ] git diff --check passes, or every existing/pre-existing issue is identified accurately.
- [ ] Working-tree status reviewed; pre-existing user changes preserved.
- [ ] Before/after Git status is available for any claim that staging or repository state was unchanged.
- [ ] Implementation report maps requirements/findings to files and evidence.
- [ ] Unverified behavior, unavailable tests, limitations, and open questions are explicit.
- [ ] No commit or push was made unless explicitly authorized.
