# WP-05A — Persistence Foundation

Parent Trello Card: https://trello.com/c/4ojeeFID/8-wp-05a-persistence-foundation

## Design Boundary ที่อนุมัติแล้ว

- `CTGKGridPersistence` รับผิดชอบ Instance/Lifecycle/Configuration Persistence ต่อไป
- `CTGKGridEntryMappingReducer` ร่วมกับ `CTGKGridEntryMappingSnapshotStorage` เป็น Canonical Trading State Persistence Authority
- Canonical Trading State ประกอบด้วย Entry Request/Deal Associations, Position Mappings, Normal Level States และ Anchor State
- Anchor State และ Position Mapping ที่เปลี่ยนจาก Close Event เดียวกัน ต้องเป็น Durable Logical Transition เดียวกัน
- Schema คง V1 โดย V1 ฉบับปรับปรุงต้องมี Anchor State เป็น Required Field; ไม่รองรับ V1 รูปแบบเก่าและไม่ทำ Migration/Backward Compatibility
- Anchor State ที่ขาด/Invalid ใน Snapshot หรือ Persistence/Recovery Inconsistency ต้อง Fail Closed / Recovery Required
- ห้ามสร้าง Anchor Persistence Authority ซ้ำใน `GridPersistence`

## Implementation Breakdown

| Card | ผลลัพธ์ | สถานะ | Dependency |
|---|---|---|---|
| [WP-05A.1 — Anchor State Model](https://trello.com/c/K2y13ndo/12-wp-05a1-anchor-state-model) | Reducer In-memory Anchor State, Initialization/Reset, Validation, Getter และ Unit Tests | Done — User Verification PASS, CTO Code Review APPROVED และผู้ใช้ยืนยันปิด Card เมื่อ 2026-11-21 | ไม่มี |
| [WP-05A.2 — Anchor State Transitions](https://trello.com/c/1fjrNdNX/13-wp-05a2-anchor-state-transitions) | Anchor Mapping Activation, Partial/Full Close, reason-free Atomic Reducer Transition, WAIT_RETURN normalization, replay/idempotency และ Tests | **Done — CTO Code Review APPROVED 2026-11-24; CR-01/CR-02/CR-03 resolved; user-reported full no-trade Grid Regression PASS.** See [CODE_REVIEW.md](Phase-1.2/CODE_REVIEW.md) and [IMPLEMENTATION_REPORT.md](Phase-1.2/IMPLEMENTATION_REPORT.md) §10–11 | WP-05A.1 |

WP-05A.2 ครอบคลุม Durable Anchor/Level Transition, Journal Replay และ Snapshot compatibility ที่จำเป็นต่อ Atomic State ตาม SPEC; Cards ถัดไปจะจัดการ Persistence/Recovery Hardening ที่เหลือและ Integration โดยแต่ละ Card ต้องมี Scope, SPEC, TEST_PLAN และ User Approval แยกต่างหากก่อนเริ่ม Implementation

## WP-05A.1 Handoff

- Specification: [SPEC.md](Phase-1.1/SPEC.md)
- Test Plan: [TEST_PLAN.md](Phase-1.1/TEST_PLAN.md)
- Implementation Report: [IMPLEMENTATION_REPORT.md](Phase-1.1/IMPLEMENTATION_REPORT.md)
- CTO Code Review: [CODE_REVIEW.md](Phase-1.1/CODE_REVIEW.md)
- Trello: https://trello.com/c/K2y13ndo/12-wp-05a1-anchor-state-model

## WP-05A.2 Handoff — Approved 2026-11-23

- Specification: [SPEC.md](Phase-1.2/SPEC.md)
- Test Plan: [TEST_PLAN.md](Phase-1.2/TEST_PLAN.md)
- Freebuff Task: [IMPLEMENTATION_TASK.md](Phase-1.2/IMPLEMENTATION_TASK.md)
- Implementation Report: [IMPLEMENTATION_REPORT.md](Phase-1.2/IMPLEMENTATION_REPORT.md) — user-reported Compile/Test PASS 2026-11-23
- CTO Code Review: [CODE_REVIEW.md](Phase-1.2/CODE_REVIEW.md) — **APPROVED 2026-11-24**; CR-01/CR-02/CR-03 resolved
- Review fixes: [IMPLEMENTATION_REPORT.md](Phase-1.2/IMPLEMENTATION_REPORT.md) §§10–11 — CR-01/CR-02/CR-03 implemented; user-reported full Grid Regression PASS
- Trello: https://trello.com/c/1fjrNdNX/13-wp-05a2-anchor-state-transitions
- Approved scope: reason-free Full Close transition; Position Identifier as canonical Position identity; Partial Close retains ACTIVE; WAIT_RETURN normalized to READY; state-based idempotency; no Closing Deal History integration.
- Baseline gate: PASSED 2026-11-23. User ran all current Grid Regression test files and reported PASS; all tests that open orders on the Demo account were excluded. No fresh compile was run because source had not changed. Trello moved to In Progress; Freebuff is authorized to implement the approved WP-05A.2 scope.

## Workflow Gates

1. Historical Pre-change Baseline ของ WP-05A.1 มาจากผลผู้ใช้รายงานเมื่อ 2026-11-20: no-trade Grid Test EAs 19 ไฟล์ผ่าน; ผลนี้ไม่ใช่ Baseline ของ WP-05A.2 เพราะ Source เปลี่ยนหลังจากนั้น. WP-05A.2 ต้องรอผู้ใช้รัน Current no-trade Grid Regression Inventory (ไม่รวม Demo Trade Request Tests) และรายงานผลใหม่ก่อน Freebuff แก้ Source
2. ผู้ใช้อนุมัติเริ่ม WP-05A.1 เมื่อ 2026-11-21; Card ถูกย้ายจาก Ready ไป In Progress เพื่อส่งให้ Freebuff
3. Freebuff Implement ตาม SPEC เท่านั้น และจัดทำ `IMPLEMENTATION_REPORT.md`
4. ผู้ใช้รายงานเมื่อ 2026-11-21 ว่า MetaEditor Compile และ Run Tests ผ่านทั้งหมด
5. CTO ตรวจ Diff เทียบ SPEC/TEST_PLAN/Architecture แล้วบันทึก `CODE_REVIEW.md` เป็น APPROVED
6. เอกสารและสถานะโครงการได้รับการอัปเดต; WP-05A.1 ปิดแล้วใน Trello `Done` และ Mark Complete หลัง User Confirmation เมื่อ 2026-11-21
7. WP-05A.2 SPEC/TEST_PLAN approved 2026-11-23; pre-change no-trade baseline passed; Freebuff implemented the scope and review fixes CR-01/CR-02/CR-03. Freebuff MetaEditor Compile passed for both Adapter consumers (0 errors, 0 warnings); user reported the full no-trade Grid Regression suite PASS on 2026-11-24. CTO Code Review APPROVED 2026-11-24; user authorized closure and the Trello card is Done.

ไม่มี Demo หรือ Live Trade Request ได้รับอนุญาต
