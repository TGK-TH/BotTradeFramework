# Grid EA

## ขอบเขต

เอกสารชุดนี้อธิบายการออกแบบและส่วนประกอบ Grid ในปัจจุบัน รวมถึงข้อกำหนดที่ตกลงไว้สำหรับ Grid V1 โดยแยกสิ่งที่มีใน Source Code แล้วออกจากสิ่งที่ยังรอพัฒนา

Grid เป็น EA หนึ่งตัวใน BotTradeFramework ไม่ใช่ขอบเขตของ Framework ทั้งหมด

## เอกสาร

- [Architecture](architecture.md) — ภาพรวมส่วนประกอบและขอบเขตปัจจุบัน
- [Identity](modules/identity.md) — Grid Instance ID และ Magic Number
- [Persistence](modules/persistence.md) — Snapshot และการกู้คืนสถานะ
- [Grid Tests](Testing/testing.md) — รายชื่อ Test EA ขั้นตอน และผลทดสอบที่ผู้ใช้รายงาน
- [ADR-001: Identity และ Persistence](Decisions/ADR-001-grid-identity-and-persistence.md)
- [ADR-002: Chart ID ไม่ใช่ Persistence Identity](Decisions/ADR-002-chart-id-is-not-persistence-identity.md)
- [Phase: Grid Integration Testing](Phases/phase-grid-integration-testing.md)
- [Phase: Grid State Machine](Phases/phase-grid-state-machine.md)

## ข้อกำหนด Grid V1 ที่ตกลงไว้ แต่ยังไม่เท่ากับการพัฒนาเสร็จ

Grid ตั้งใจให้หนึ่ง EA/chart instance จัดการ Grid ของตัวเอง แยกด้วย Symbol และ Magic Number โดยใช้ Anchor จากราคาที่ Fill จริง จัดการระดับราคาและการเปิด Position ซ้ำหลัง TP รวมถึงจัดการการเปลี่ยน Mode/Step และการกู้คืนหลัง Restart

รายละเอียดเหล่านี้เป็นข้อกำหนดสำหรับการพัฒนาต่อ ไม่ใช่คำยืนยันว่า Grid State Machine หรือ Order Execution ทำงานครบถ้วนแล้ว ดูสถานะ Phase ล่าสุดใน `PROJECT_STATUS.md`
