# TGK Implementation Report Checklist

Use the active Card's existing `IMPLEMENTATION_REPORT.md` structure. Do not create a second report if one already exists.

The report should let the Product Owner and CTO understand exactly what changed without relying on chat history.

## Required contents

1. **Task identity and authorization**
   - Work Package/Card, SPEC and TEST_PLAN paths, approved scope, implementation date, and status.
2. **Changed files**
   - Exact paths and concise purpose of each change.
   - Identify files inspected but not changed only when relevant to explain a design choice.
3. **Implementation summary**
   - Map each acceptance criterion or CTO finding ID to the implementation and test that addresses it.
   - State explicitly when a finding is deferred or accepted unchanged, with the approved reason.
4. **Compile evidence (separate section)**
   - Exact affected program paths compiled, including all consumers of changed `.mqh` files.
   - Command/environment used, log path, exact MetaEditor result line, and confirmation of 0 errors / 0 warnings.
   - If compilation was unavailable or incomplete, state the exact blocker and do not claim compile pass.
5. **Test evidence (separate section)**
   - Tests added/changed and their purpose.
   - Tests actually run by the Implementer, with exact result and environment.
   - Tests not run and why. Explicitly state that MT5 suites remain for Product Owner when required by `AGENTS.md`.
6. **Quality checks**
   - Full diff reviewed, `git diff --check`, static scans, and other checks actually performed.
7. **Known limitations and handoff**
   - Unverified behavior, open questions, deferred findings, known limitations, and exact next action for Product Owner.

## Evidence language

Use precise attribution:
- "Implementer compiled..." only when the Implementer actually compiled and can provide logs/results.
- "Product Owner reported..." for results supplied by the user.
- "Static inspection..." for source reading or grep checks.
- "Exploratory observation..." for informal UI activity.
- "Not run" for checks not executed.

Never infer a test pass from compile success, a successful build from static inspection, or official runtime verification from exploratory UI activity.
