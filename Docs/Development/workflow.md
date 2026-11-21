# Workflow การพัฒนา

## บทบาทและความรับผิดชอบ

- **ChatGPT — CTO / Technical Lead:** ร่วมออกแบบ Architecture และ Contract, แบ่ง WP/Phase/Implementation Cards, จัดทำ Developer Specification, ตรวจ Code หลังผู้ใช้ยืนยัน Compile/Test PASS, บันทึก Review Findings และอัปเดตเอกสารทางเทคนิคหลัง Review ผ่าน
- **Freebuff — Developer Agent:** อ่าน `AGENTS.md` และไฟล์ Specification จาก Repository โดยตรง, Implement Source Code และ Tests ภายใน Scope ที่อนุมัติ, รายงานไฟล์ที่เปลี่ยนและหลักฐานใน `IMPLEMENTATION_REPORT.md` ห้ามเปลี่ยน Contract หรือขยาย Scope เอง และไม่ต้องติดตั้งหรือใช้ Serena MCP
- **ผู้ใช้ — Product Owner / QA:** อนุมัติ Design/Scope, สั่ง Freebuff ทำงาน, Compile และ Run Tests ใน MetaEditor/MT5, รายงานผลจริง และอนุมัติงานถัดไป

ChatGPT ทำหน้าที่ CTO/Review ไม่ใช่ผู้ Implement: ห้าม ChatGPT แก้ Source Code แทน Freebuff ภายใต้ Workflow นี้ เว้นแต่ผู้ใช้จะเปลี่ยนข้อตกลงอย่างชัดเจน

## ลำดับการทำงานต่อ Implementation Card

1. ร่วมกันกำหนด Design, Contract, Dependency, Scope และ Acceptance Criteria; ต้องได้รับอนุมัติจากผู้ใช้
2. สร้างหรือปรับ Trello Card และจัดทำ `SPEC.md` กับ `TEST_PLAN.md` แยกกัน โดยระบุไฟล์ที่อนุญาตให้แก้และข้อห้ามอย่างชัดเจน
3. ย้าย Card ไปสถานะพร้อม Implement แล้วผู้ใช้จึงสั่ง Freebuff ให้ทำงาน Freebuff อ่านไฟล์ใน Repository โดยตรง ไม่ต้องพึ่ง Serena MCP หรือประวัติ Chat
4. เมื่อ Implement เสร็จ Freebuff จัดทำ `IMPLEMENTATION_REPORT.md` และส่ง Card ไป User Verification
5. ผู้ใช้ Compile และ Run Tests ก่อน Formal Code Review เท่านั้น หากไม่ผ่าน ให้ Freebuff แก้แล้วกลับมาทดสอบซ้ำ
6. เมื่อผู้ใช้ยืนยัน Compile/Test PASS แล้ว จึงส่ง Card ไป Code Review และแจ้ง ChatGPT
7. ChatGPT ตรวจ Diff/Source เทียบกับ Specification, Tests, Acceptance Criteria และหลักฐานที่ผู้ใช้รายงาน แล้วบันทึกผลใน `CODE_REVIEW.md`
8. Review มีผล `APPROVED`, `CHANGES_REQUESTED` หรือ `BLOCKED` หากต้องแก้ ให้ Freebuff แก้ตาม Finding IDs และผู้ใช้ Compile/Test ซ้ำก่อนส่ง Review รอบถัดไป
9. เมื่อ User Verification PASS และ Code Review APPROVED แล้ว ChatGPT อัปเดตเอกสารและสถานะ จากนั้นปิด Card ได้เมื่อผู้ใช้ยืนยัน
10. หยุดรอผู้ใช้อนุมัติงาน/Phase ถัดไปเสมอ

ไฟล์ Handoff มาตรฐานต่อ Card:
- `SPEC.md`: Objective, Scope/Out of Scope, Dependencies, Allowed Files, Technical Contract, Constraints, Acceptance Criteria
- `TEST_PLAN.md`: Preconditions, Test IDs/Scenarios, Expected Results, Regression Coverage, Safety Restrictions
- `IMPLEMENTATION_REPORT.md`: Changed Files, Implementation Summary, Tests Run/Not Run, Exact Results, Remaining Issues
- `CODE_REVIEW.md`: Review Status และ Findings ที่มี ID, Severity, File/Location, Problem, Required Fix, Acceptance Condition

## Trello Lifecycle

ใช้ List ที่มีอยู่ให้ตรงกับสถานะจริง หากต้องเพิ่มหรือเปลี่ยน List ให้ตกลงกับผู้ใช้ก่อน ลำดับเป้าหมายคือ:
`Product Backlog -> Ready -> In Progress -> User Verification -> Code Review -> Done`

- User Compile/Test ไม่ผ่าน: กลับ `In Progress` เพื่อให้ Freebuff แก้
- CTO Review ขอแก้: ใช้ `Changes Requested` (หรือ List ที่ตกลงให้เทียบเท่า) แล้วกลับ User Verification ก่อน Review รอบใหม่
- ห้ามย้ายเป็น `Done` จากคำรายงานว่าเขียน Code เสร็จเพียงอย่างเดียว
- Trello ใช้ติดตามสถานะและชี้ไปยังไฟล์ใน Repository; Repository Markdown เป็นแหล่ง Contract/Technical Handoff ที่ละเอียดและเป็นหลัก

## ทำงานเป็น Phase

1. กำหนด Scope และผลลัพธ์ที่ต้องการของ Phase ก่อนแก้ไข
2. ตรวจเอกสารและโค้ดที่เกี่ยวข้อง รวมถึง Regression Tests ที่จำเป็น
3. เปลี่ยนแปลงเฉพาะ Scope ที่ได้รับอนุมัติ โดย Freebuff เป็นผู้ Implement ตาม Card
4. ตรวจ Diff, Local Links และการตรวจสอบที่ทำได้ในสภาพแวดล้อมปัจจุบัน
5. ให้ผู้ใช้ Compile/Run ใน MetaEditor/MT5 และบันทึกผลตามที่ผู้ใช้รายงาน ก่อนส่ง Formal Code Review
6. เมื่อ Code Review ผ่าน ให้ปรับ `PROJECT_STATUS.md` และ Docs ที่ได้รับผลกระทบ
7. เมื่อ Phase ปัจจุบันเสร็จ ให้สรุปผลและหยุดรอการอนุมัติจากผู้ใช้ก่อนเริ่ม Phase ถัดไปทุกครั้ง
8. ก่อนเริ่ม Phase ให้ตรวจ Trello Card ที่ตรงกับ Scope และสถานะจริง; สร้าง Card ใหม่หรือปรับ Card เดิมให้พร้อมก่อนเริ่มงาน
9. เมื่อทำงานใน Phase เสร็จ ให้อัปเดต Trello Card ให้ตรงกับผลจริง สถานะ Acceptance และงานค้าง โดยแยก User Verification ออกจาก CTO Code Review

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
