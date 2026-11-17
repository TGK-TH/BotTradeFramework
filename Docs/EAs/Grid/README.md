# Grid EA

## ขอบเขต

เอกสารชุดนี้อธิบาย Grid ในฐานะ EA หนึ่งตัวภายใน BotTradeFramework ซึ่งเป็น Repository สำหรับหลาย EA ไม่ใช่ Framework ทั้งหมด เอกสารแยก Source/Behavior ที่ Implemented แล้วออกจาก Design ที่ตกลงแต่ยังไม่ Implement

## จุดเริ่มต้นที่ควรอ่าน

1. [Master Roadmap และ Grid V1 Definition of Done](ROADMAP.md) — แผนหลักจน Grid V1 เสร็จและเกณฑ์ปิดงาน
2. [Architecture](architecture.md) — ส่วนประกอบใน Source และ Dependency Boundaries
3. [Grid Tests](Testing/testing.md) — Test Inventory, Regression Policy และผลที่ผู้ใช้รายงาน
4. [Current Project Status](../../../PROJECT_STATUS.md) — Work Package ปัจจุบันและขั้นตอนถัดไป

## เอกสารเฉพาะด้าน

- [Identity](modules/identity.md) — Grid Instance ID และ Magic Number
- [Persistence](modules/persistence.md) — Snapshot และการกู้คืนสถานะ
- [ADR-001: Identity และ Persistence](Decisions/ADR-001-grid-identity-and-persistence.md)
- [ADR-002: Chart ID ไม่ใช่ Persistence Identity](Decisions/ADR-002-chart-id-is-not-persistence-identity.md)
- [Grid Integration Testing](Phases/phase-grid-integration-testing.md)
- [Grid State Machine](Phases/phase-grid-state-machine.md)
- [Grid Lifecycle Integration](Phases/phase-grid-lifecycle-integration.md)
- [Grid Order Execution — Close Adapter](Phases/phase-grid-order-execution.md)
- [Grid Order Execution — Demo Integration](Phases/phase-grid-order-execution-demo-integration.md)
- [Grid Level Engine — Design](Phases/phase-grid-level-engine-design.md)
- [Grid Level Engine — Implementation Round 1](Phases/phase-grid-level-engine-implementation-round-1.md)
- [Grid Level Runtime Coordinator — Round 1](Phases/phase-grid-level-runtime-coordinator-round-1.md)
- [Grid Entry Execution Adapter — Persistence/Mapping Round 1](Phases/phase-grid-entry-execution-adapter-round-1.md)
- [Grid Entry Execution Policy — Design, Contract และ Test-First](Phases/phase-grid-entry-execution-policy.md)

## Current implementation boundary

มี Source สำหรับ Identity, Snapshot/Level Persistence, State Machine, Lifecycle/Runtime Orchestration, Position Reconciliation, Close Execution Adapter, Two-sided Level Engine, Runtime Coordinator และ Entry Mapping Storage/Reducer/Snapshot Rotation แล้ว โดยผล Compile/Runtime เป็นผลที่ผู้ใช้รายงานตาม Phase Notes

Grid Entry Execution Policy Phase 1–2 ได้รับอนุมัติและ Finalized แล้ว; WP-01 สร้าง Policy Header ตาม Contract และผ่าน Static Review แล้ว แต่ยังรอ Compile/Run Test EA 44 Cases และ Grid Regression ใน MetaEditor/MT5 ก่อนเริ่ม WP-02

**ข้อสำคัญ:** การที่ Components แยกส่วนผ่าน Unit/Integration Tests ไม่ได้แปลว่า Grid V1 เสร็จ ต้องเชื่อม Production EA Event Handlers และทดสอบ End-to-End ตาม [Definition of Done](ROADMAP.md)
