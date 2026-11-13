# Phase: จัดโครงสร้างเอกสารสำหรับหลาย EA

- สถานะ: เสร็จสมบูรณ์
- วันที่: 2026-10-23
- Scope: เอกสารและ Workflow เท่านั้น

## เป้าหมาย

ปรับโครงสร้างเอกสารให้สอดคล้องกับเป้าหมายของ BotTradeFramework ซึ่งจะรองรับ EA หลายตัว โดยแยกเอกสารของ Framework ที่ใช้ร่วมกันออกจากเอกสารเฉพาะ EA

## การตัดสินใจด้านโครงสร้าง

- `Docs/Framework/` ใช้สำหรับสถาปัตยกรรมและ Module ที่ออกแบบให้ EA หลายตัวใช้ร่วมกันได้จริง
- `Docs/EAs/<EA-Name>/` ใช้สำหรับ Architecture, Logic, Configuration, Tests, Decisions และ Phase Notes ของ EA แต่ละตัว
- `Docs/Development/` ใช้สำหรับ Workflow และมาตรฐานที่ใช้กับ Repository
- `Docs/Decisions/README.md` เป็นดัชนี ADR ส่วนกลาง โดย ADR แต่ละฉบับต้องระบุ Scope
- `PROJECT_STATUS.md` ใช้สรุปสถานะปัจจุบันและขั้นตอนถัดไป ไม่ใช้แทนเอกสารเทคนิค

## การเปลี่ยนแปลง

- ย้ายเอกสาร Grid architecture, Identity, Persistence, Tests, ADRs และ Integration Testing Phase ไปไว้ใต้ `Docs/EAs/Grid/`
- ย้ายเอกสาร TestAssert/TestRunner ไปไว้ใต้ `Docs/Framework/Testing/`
- เพิ่มดัชนี Framework, ดัชนี EA, Grid README และ Development Workflow
- ปรับลิงก์ภายในและอัปเดต root `README.md`, `AGENTS.md` และ `PROJECT_STATUS.md`

## ข้อกำหนดสำคัญ

การย้ายเอกสารไม่ได้หมายความว่า Grid Identity หรือ Persistence กลายเป็น Shared Module แล้ว เนื่องจากชื่อและสัญญาการใช้งานปัจจุบันยังเฉพาะ Grid ต้องประเมินอีกครั้งเมื่อ EA ตัวอื่นต้องการใช้ความสามารถที่คล้ายกัน

## การตรวจสอบ

- ตรวจรายการไฟล์หลังย้ายและลิงก์ Markdown ภายใน Repository
- ตรวจ `git diff --check`
- ไม่มีการเปลี่ยน Source Code MQL5 และไม่มีการ Compile/Run ใน MetaEditor/MT5 ใน Phase นี้

## ขั้นตอนถัดไป

ขั้นตอนพัฒนาถัดไปที่วางแผนไว้คือ Grid State Machine แต่ยังไม่เริ่มจนกว่าผู้ใช้จะอนุมัติอย่างชัดเจน ก่อนเริ่ม Feature หรือ Refactor ของ Grid ต้องรัน Grid Regression Tests ที่เกี่ยวข้องก่อน
