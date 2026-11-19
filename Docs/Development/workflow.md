# Workflow การพัฒนา

## ทำงานเป็น Phase

1. กำหนด Scope และผลลัพธ์ที่ต้องการของ Phase ก่อนแก้ไข
2. ตรวจเอกสารและโค้ดที่เกี่ยวข้อง รวมถึง Regression Tests ที่จำเป็น
3. เปลี่ยนแปลงเฉพาะ Scope ที่ได้รับอนุมัติ
4. ตรวจ Diff, Local Links และการตรวจสอบที่ทำได้ในสภาพแวดล้อมปัจจุบัน
5. ให้ผู้ใช้ Compile/Run ใน MetaEditor/MT5 เมื่อจำเป็น และบันทึกผลตามที่ผู้ใช้รายงาน
6. เมื่อ Phase เสร็จ ให้ปรับ `PROJECT_STATUS.md` และ Docs ที่ได้รับผลกระทบ
7. เมื่อ Phase ปัจจุบันเสร็จ ให้สรุปผลและหยุดรอการอนุมัติจากผู้ใช้ก่อนเริ่ม Phase ถัดไปทุกครั้ง รวมถึงกรณีที่ Kickoff Prompt เคยอนุมัติ Roadmap แบบครอบคลุมไว้แล้ว
8. ก่อนเริ่ม Phase ให้ตรวจ Trello Card ที่ตรงกับ Scope และสถานะจริง; สร้าง Card ใหม่หรือปรับ Card เดิมให้พร้อมก่อนเริ่มงานเสมอเมื่อจำเป็น
9. เมื่อทำงานใน Phase เสร็จ ให้อัปเดต Trello Card ให้ตรงกับผลจริง สถานะ Acceptance และงานค้างทุกครั้ง โดยแยกผล Compile/Runtime ที่ผู้ใช้ยืนยันออกจากการตรวจของ Assistant

## ขอบเขตการเขียนเอกสาร

- **Framework:** สิ่งที่ออกแบบให้ EA หลายตัวใช้ร่วมกันได้จริง
- **EA-specific:** Strategy Logic, State Machine, Position Management, Inputs และ Tests เฉพาะ EA
- **Development:** วิธีทำงานและมาตรฐานที่ใช้กับ Repository ทั้งหมด
- **Decisions:** บันทึกเหตุผลการตัดสินใจ โดยระบุ Scope ให้ชัดเจน
- **Project Status:** สรุปสถานะปัจจุบันและขั้นตอนถัดไป ไม่ทำซ้ำเอกสารเชิงเทคนิค

## Documentation Consistency Gate

ก่อนปิด WP/Phase หรือ Documentation Maintenance ทุกครั้ง ต้องผ่าน [Documentation Consistency Gate](documentation-consistency-gate.md) เพิ่มเติมจากการ Review และการอัปเดตเอกสารตามปกติ โดยต้องตรวจความสอดคล้องเชิงความหมายระหว่าง `PROJECT_STATUS.md`, Roadmap/README, Architecture, Testing, Phase Notes, ADRs, Source/Tests และ Serena current-phase memory ตามขอบเขตที่ได้รับผลกระทบ

- ตรวจทั้งข้อความที่ยืนยันว่ามีและไม่มี Feature/Module, สถานะ WP, Test Inventory/จำนวน Test, ผล Compile/Runtime, Next Step และ Approval Boundary
- ค้นหาข้อความเก่าหรือขัดแย้งในเอกสารและ Memory; เก็บประวัติที่ถูกต้องในอดีตไว้ แต่ระบุวันที่/บริบทและชี้ไปยังสถานะปัจจุบัน
- อ่าน Diff ทั้งหมด, รัน `git diff --check`, ตรวจ Local Markdown Links และตรวจ Test Inventory กับไฟล์จริงเมื่อเกี่ยวข้อง
- หากยังมีข้อขัดแย้งหรือหลักฐานไม่ครบ ห้ามรายงานว่า WP/Phase ผ่าน Gate หรือ Complete

## สถานะหลักฐาน

ในเอกสารให้แยกให้ได้ระหว่าง:
- **Implemented:** มีอยู่ใน Source Code
- **User-verified:** ผู้ใช้ยืนยันผล Compile/Runtime หรือพฤติกรรมแล้ว
- **Agreed, not implemented:** ข้อกำหนดที่ตกลงแล้วแต่ยังไม่ได้พัฒนา
- **Open:** ยังต้องตัดสินใจหรือทดสอบเพิ่มเติม

การตรวจ Diff หรือ Link ไม่ใช่หลักฐานว่า MQL5 Compile/Runtime ผ่าน
