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
| [WP-05A.1 — Anchor State Model](https://trello.com/c/K2y13ndo/12-wp-05a1-anchor-state-model) | Reducer In-memory Anchor State, Initialization/Reset, Validation, Getter และ Unit Tests | In Progress; Freebuff implementation authorized after recorded baseline | ไม่มี |
| [WP-05A.2 — Anchor State Transitions](https://trello.com/c/1fjrNdNX/13-wp-05a2-anchor-state-transitions) | Anchor Mapping Activation, Partial Close, Full TP/NON_TP Close, Atomic Reducer Transition และ Tests | Product Backlog; planning placeholder, SPEC/TEST_PLAN ยังไม่จัดทำ | WP-05A.1 |

WP-05A Cards ในลำดับถัดไปจะครอบคลุม Journal Persistence, Snapshot Persistence และ Integration/Hardening โดยแต่ละ Card ต้องมี Scope, SPEC, TEST_PLAN และ User Approval แยกต่างหากก่อนเริ่ม Implementation

## WP-05A.1 Handoff

- Specification: [SPEC.md](Phase-1.1/SPEC.md)
- Test Plan: [TEST_PLAN.md](Phase-1.1/TEST_PLAN.md)
- Trello: https://trello.com/c/K2y13ndo/12-wp-05a1-anchor-state-model

## Workflow Gates

1. Pre-change Grid Regression Baseline บันทึกจากผลที่ผู้ใช้รายงานเมื่อ 2026-11-20: no-trade Grid Test EAs ทั้ง 19 ไฟล์ผ่าน; Demo Trade Request Test แยก Safety Gate และไม่รวม
2. ผู้ใช้อนุมัติเริ่ม WP-05A.1 เมื่อ 2026-11-21; Card ถูกย้ายจาก Ready ไป In Progress เพื่อส่งให้ Freebuff
3. Freebuff Implement ตาม SPEC เท่านั้น และจัดทำ `IMPLEMENTATION_REPORT.md`
4. ผู้ใช้ Compile และ Run Tests ใน MetaEditor/MT5; ใช้ List `MT5 Testing` บน Board เป็น User Verification
5. ChatGPT เริ่ม Formal Code Review หลังผู้ใช้รายงาน PASS เท่านั้น
6. หาก Review ขอแก้ Freebuff แก้ไข และผู้ใช้ Compile/Test ซ้ำก่อนส่ง Review รอบใหม่
7. หลัง Review APPROVED และ Documentation Consistency Checks ผ่าน จึงปิด Card และหยุดรอ Approval ก่อน WP-05A.2

ไม่มี Demo หรือ Live Trade Request ได้รับอนุญาต
