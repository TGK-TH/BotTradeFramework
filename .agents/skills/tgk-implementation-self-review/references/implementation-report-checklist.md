# TGK Implementation Report Checklist

Use the active Card's existing IMPLEMENTATION_REPORT.md structure. Do not create a second report if one already exists.

## Required contents

1. **Task identity and authorization**
   - Work Package/Card, SPEC and TEST_PLAN paths, approved scope, implementation date, and status.
2. **Changed files**
   - Exact paths and concise purpose of each change.
   - Identify files inspected but not changed only when relevant to explain a design choice.
3. **Implementation summary**
   - Map each acceptance criterion or CTO finding ID to implementation, test, and evidence.
   - State explicitly when a finding is deferred or accepted unchanged, with approved reason.
   - For remediation, include a Finding Closure Matrix: ID, status (FIXED/OPEN/DEFERRED), exact code/test location, acceptance condition, evidence, and remaining limitation.
4. **Compile evidence (separate section)**
   - Exact affected program paths compiled, including all consumers of changed .mqh files.
   - Command/environment used, log path, exact MetaEditor result line, and confirmation of 0 errors / 0 warnings.
   - If compilation was unavailable or incomplete, state exact blocker and do not claim compile pass.
5. **Test evidence (separate section)**
   - Tests added/changed and purpose.
   - Tests actually run by Implementer, exact result and environment.
   - Tests not run and why. Explicitly state MT5 suites remain for Product Owner when required by AGENTS.md.
6. **Self-review evidence**
   - Requirement-to-Code/Test Trace and Acceptance Evidence Audit.
   - For remediation: API Semantics Audit and Adversarial Review summary, including challenged failure modes and outcome.
   - Regression matrix for all prior findings, not only findings in the latest round.
7. **Quality checks**
   - Full diff reviewed, git diff --check, static scans, and other checks actually performed.
   - Git status before and after work when making claims about preservation of staged/unstaged/untracked state. Include exact status evidence or a concise accurate summary.
8. **Known limitations and handoff**
   - Unverified behavior, open questions, deferred findings, known limitations, and exact next action for Product Owner.

## Evidence language

Use precise attribution:
- "Implementer compiled..." only when the Implementer actually compiled and can provide logs/results.
- "Product Owner reported..." for results supplied by the user.
- "Static inspection..." for source reading or grep checks.
- "Adversarial review..." for a documented challenge of failure modes; identify what was challenged and what was found.
- "Exploratory observation..." for informal UI activity.
- "Not run" for checks not executed.

Never infer a test pass from compile success, a successful build from static inspection, or official runtime verification from exploratory UI activity. Do not claim Git staging or working-tree state was unchanged without before/after evidence.
