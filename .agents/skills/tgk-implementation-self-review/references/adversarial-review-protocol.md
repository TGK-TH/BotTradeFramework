# Adversarial Remediation Review Protocol

## Purpose and trigger

This protocol is mandatory for every implementation/remediation cycle after a CTO Review Reject. It is designed to prevent repeated review rounds caused by local fixes that do not prove the complete contract. It supplements, and does not override, AGENTS.md, the active SPEC.md, TEST_PLAN.md, or the CTO's authorized finding handoff.

The Implementer remains responsible for implementation and self-review. Completing this protocol is not CTO approval.

## 0. Freeze scope and establish baseline

1. Read the current CODE_REVIEW.md, exact finding handoff, active SPEC.md, TEST_PLAN.md, AGENTS.md, and applicable Skill references.
2. Record allowed files and prohibited actions before editing.
3. Capture git status --short --untracked-files=all before editing. Preserve staged, unstaged, and untracked changes; do not use destructive Git operations.
4. Create a Finding Closure Matrix for all current findings and a Regression Matrix for every prior finding, including those previously marked fixed.
5. If a finding requires changing product behavior, public contract, architecture, or out-of-scope files, stop and request CTO/Product Owner direction.

## 1. Requirement-to-Code Trace

For every relevant Acceptance Criterion and finding:

- Quote or summarize the exact requirement and define its observable pass condition.
- Trace the full execution path: entry point → preconditions → data acquisition → validation → state/decision → persistence/side effect → returned status/report.
- Identify exact functions/files and their callers/consumers.
- Map the requirement to tests that actually reach the relevant path.
- Identify what happens on every failure/partial-data branch.
- Verify that the test's fixture reaches the intended guard; document earlier guards separately.

Do not stop at locating a function with a matching name. Trace how its result is consumed and whether a later branch can bypass or contradict it.

## 2. API Semantics Audit

For each consequential platform/library/API operation, verify the actual contract using authoritative documentation or declarations available in the environment. Record the source or exact declaration inspected.

Audit at least:

- Function signature and return type.
- Exact success/failure convention and whether return values are counts, booleans, handles, or status codes.
- Whether the operation can partially succeed or return a sentinel such as zero.
- Whether a void-returning operation exposes any failure status.
- Error-state lifecycle: whether GetLastError or equivalent is reset, overwritten, or meaningful after this operation; never assume a clean error value proves success.
- Numeric conversion/parsing behavior, including malformed trailing characters, overflow, underflow, precision loss, NaN/Infinity, and signed/unsigned boundaries.
- Enumeration semantics: valid index range, possible holes/failures, and whether a failed item read makes the whole scan incomplete.
- File encoding, string length, terminator, and write-count semantics where persistence is involved.
- Buffer/capacity and identifier validity rules.

If authoritative semantics cannot be established, mark the assumption unresolved, choose a fail-closed behavior where safe and within scope, or ask for direction. Do not present an assumption as verified fact.

## 3. Adversarial Review

Review the implementation as if trying to make it return success/PASS incorrectly. For each relevant path, ask:

**"How could incomplete, stale, malformed, contradictory, or partially available evidence still cause this code to report success?"**

Challenge at least the applicable cases:

- Zero/invalid tickets, identifiers, handles, indices, or timestamps.
- Missing/failed property reads and partially populated structures.
- Empty, truncated, oversized, duplicated, reordered, or extra persisted fields/records.
- Malformed numeric values, overflow, precision loss, invalid signs, non-finite values, and trailing junk.
- Partial file writes, failed flush/durability assumptions, interrupted append, and restart during each persistence boundary.
- Incomplete History/API enumeration and ambiguous NOT_FOUND versus IO_ERROR.
- Buffer overflow, truncation, first-element assumptions, stale array contents, and index/capacity boundary errors.
- Duplicate/replayed callbacks, conflicting evidence, multiple related entities, and out-of-order events.
- Boolean/status propagation through callers: ignored return values, inverted conditions, default-success initialization, and fall-through.
- Alternate public entry points that bypass safety gates.
- Tests that pass because an earlier unrelated guard rejects the fixture.
- Reports/checklists that mark PASS without direct evidence.

For every plausible failure mode, record one of: (a) prevented by a specific guard and test, (b) safely reported incomplete/error, (c) not applicable with reason, or (d) unresolved/open. Do not dismiss a case solely because it is unlikely.

## 4. Acceptance Evidence Audit

For each AC, make an evidence table:

| AC | Required fact | Evidence source | Exact entity/record | Complete/valid? | Result |
|---|---|---|---|---|---|

Verify:

- Evidence is for the exact order/deal/position/session/record under evaluation, not an arbitrary first element or a merely related entity.
- Every required property is valid before aggregation or correlation.
- A complete snapshot/enumeration is established before interpreting absence.
- The code distinguishes confirmed positive evidence, authoritative absence, and incomplete/unknown evidence.
- Every PASS has direct evidence for the exact acceptance condition.
- A request being sent, a function being called, a nonzero value, or GetLastError()==0 is not automatically proof of success.
- Any untested behavior is labelled NOT_TESTED, not PASS.

If the acceptance condition cannot be proven with available evidence, do not weaken the condition. Report the limitation and keep the AC/finding open.

## 5. Finding Closure Matrix and regression

Maintain one row per current finding and one regression row per prior finding:

| ID | Required correction | Acceptance condition | Code/test location | Evidence | Status |
|---|---|---|---|---|---|

Use only:
- **FIXED** — code and evidence demonstrate the exact acceptance condition.
- **OPEN** — not yet satisfied, evidence missing, or behavior remains uncertain.
- **DEFERRED** — explicitly outside this authorized scope, with the approved reason/reference.

A code change alone is not evidence of closure. Re-open a previously fixed finding if the current implementation regresses or its original evidence no longer applies. Do not mark a finding fixed based only on the Implementer's assertion.

## 6. Final Diff & Report Audit

Before handoff:

1. Review the complete diff, including unrelated-looking changes and generated files.
2. Confirm every changed file is authorized; identify accidental edits.
3. Run git diff --check and report any pre-existing issue separately.
4. Compare final Git status with the captured baseline. State exactly which pre-existing changes were preserved and which new files/changes were introduced. Never claim staging was unchanged without before/after evidence.
5. Verify the implementation report against source, logs, tests, and Git evidence. Remove unsupported [x]/PASS claims.
6. Confirm no commit, push, staging operation, Tester run, Trade Request, or other prohibited action occurred.
7. Confirm Compile PASS, Implementer self-review, Product Owner test PASS, and CTO Review PASS are described as separate gates.
8. List tests not run and exact next owner/action.

## Required handoff package

The remediation handoff must include:

1. Finding Closure Matrix for all current findings.
2. Regression Matrix for all prior findings.
3. Requirement-to-Code/Test Trace for every affected AC.
4. API Semantics Audit with source/declaration and unresolved assumptions.
5. Adversarial Review cases and disposition.
6. Acceptance Evidence Audit showing why each PASS is justified.
7. Compile evidence, exact paths, environment, logs, and 0 errors/0 warnings if claimed.
8. Tests run/not run, who ran them, and results.
9. Final diff/Git status evidence and accurate implementation report.
10. Explicit limitations and the next required Product Owner action.

## Stop conditions

Stop and request direction instead of guessing when:
- The finding conflicts with the active SPEC or requires a product/architecture decision.
- Required API semantics cannot be verified and no safe in-scope handling exists.
- Evidence needed for an AC is unavailable or cannot be made authoritative within scope.
- A fix requires out-of-scope files or changes.
- The test environment or compile gate is unavailable and the report would otherwise imply success.
