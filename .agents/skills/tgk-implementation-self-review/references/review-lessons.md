# TGK CTO Review Lessons

This is a compact set of recurring failure patterns extracted from the WP-05A.2, WP-05A.3, and WP-05B review records. It is a prevention checklist, not a replacement for the active SPEC, TEST_PLAN, or current CODE_REVIEW.

## WP-05A.2 — Anchor State Transitions

### CR-01: Complete the lifecycle, not only the forward transition
The initial implementation could leave the canonical Anchor state at `WAIT_ACTIVATION` after the Engine crossed its activation threshold. That blocked later entry/mapping confirmation and could persist across restart.

**Preventive check:** Trace every state transition end-to-end across Engine signal, Coordinator gate, Adapter append, Reducer validation, Journal replay, and Snapshot restore. Verify the durable transition back to READY for both BUY and SELL.

### CR-02: Validate before durable append
An invalid Anchor activation could be appended before Reducer validation.

**Preventive check:** Validate healthy canonical context, exact expected prior state, absence of conflicting mapping, and matching pending activation before Journal append. Invalid or duplicate paths must not append or mutate state. Confirmation must follow durable success.

### CR-03: Directional coverage is not symmetric by assumption
A BUY activation test did not prove the SELL downward-activation path.

**Preventive check:** Add a real Coordinator → Adapter → Journal → Reducer test for SELL and assert durable record count, final state, pending-signal clearing, and duplicate behavior.

## WP-05A.3 — Persistence test fixture validity and evidence accuracy

### F-01: A fixture must reach the invariant it claims to test
An orphan `POSITION_MAPPING` fixture lacked the accepted Request/Execution/Deal Association. Replay rejected it during request lookup, so it did not exercise the intended Anchor `WAIT_ACTIVATION` invariant.

**Preventive check:** Construct a legal event sequence (including prerequisite accepted records), then trigger the target event and assert the intended recovery/error state and absence of mapping. Keep earlier fail-closed cases separately labelled as tests of their actual earlier guard.

### F-02: Do not overstate exploratory UI activity as official verification
An exploratory MT5 UI run was described in a way that could be mistaken for authoritative Runtime Verification.

**Preventive check:** Distinguish static inspection, Implementer compile, exploratory/manual observation, and Product Owner's official MetaEditor/MT5 verification. Identify who ran each check and when. Never label exploratory activity as official test evidence.

## WP-05B — Runtime State Restoration

### F-01 / F-02: Validate the complete canonical persisted configuration
Hydration initially accepted caller-supplied geometry/identity or mode without validating all fields against the Reducer's canonical persisted configuration. A geometry shift could preserve level count while moving every level price.

**Preventive check:** Validate identity, symbol, magic, mode, epoch, bounds, anchor, step, and persisted level count against canonical committed state before applying runtime state. Equal counts alone do not prove equal geometry.

### F-03: Close every alternate path while a safety gate is pending
A public `Reconcile()` path could still mutate state while reconciliation was pending.

**Preventive check:** Enumerate all public mutation/entry points and put the pending-gate rejection before snapshot validation, baseline mutation, and every side effect. A method named Reconcile must not implicitly release a gate unless the contract explicitly says so.

### F-05: Preserve evidence across hydration
Unresolved request hydration initially omitted the original requested volume.

**Preventive check:** Preserve every field needed to faithfully restore pending evidence; validate finite/positive values. Hydrating evidence must not accidentally confirm a request or activate its target.

### F-11: Validate tolerance, then initialize from canonical values
Requested geometry was accepted within epsilon but was then used to initialize the Engine instead of the exact persisted geometry. A tiny accepted difference could make runtime geometry diverge from persisted mappings.

**Preventive check:** Treat caller values as validation inputs; after validation, initialize from canonical persisted values. Test a within-epsilon mismatch and assert runtime geometry equals persisted geometry exactly.

### F-12: Failed re-hydration must invalidate all old runtime state
A failed second hydration could leave old Engine data and accessors visible even though a Coordinator flag had been reset.

**Preventive check:** Invalidate Engine and every runtime field/accessor before validation; on failure ensure no stale Anchor, Level, Position, Request, Candidate, or Instance data remains observable. Test success followed by failure and verify all exposed state plus canonical Reducer immutability.

## Cross-cutting review habits

- Verify the test reaches the intended guard; a failing test is not automatically proof of the intended invariant.
- Validate all preconditions before durable mutation; make atomicity and idempotency explicit.
- Test both directions and boundary/equality cases when behavior is directional.
- Keep one canonical authority for persisted state and configuration.
- Close all alternate mutation paths while a safety/reconciliation gate is active.
- Invalidate stale runtime state comprehensively after failed initialization or restoration.
- Report evidence by source: Implementer compile, Product Owner runtime tests, static checks, and exploratory observations are different categories.
- Resolve only the findings authorized for the remediation round; defer out-of-scope findings explicitly rather than silently implementing them.
