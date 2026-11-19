# Documentation Consistency Gate

## วัตถุประสงค์และเวลาที่ต้องใช้

ต้องผ่าน Gate นี้ก่อนประกาศปิด Work Package (WP), Phase หรือ Documentation Maintenance ทุกครั้ง โดยเป็น Acceptance Gate แยกจาก Implementation Review, Test Review และการอัปเดตเอกสารตามปกติ ต้องตรวจเอกสารสถานะปัจจุบันและ Durable Agent Memory ทุกส่วนที่ได้รับผลกระทบ ไม่ใช่ตรวจเฉพาะไฟล์ที่เพิ่งแก้ไข

## รายการตรวจสอบที่ต้องทำ

1. **กำหนด Baseline ของหลักฐาน**
   - ตรวจ `git status --short --untracked-files=all` และรักษา Staged/Unstaged/Untracked Changes เดิมทั้งหมด
   - ระบุ Scope, Acceptance Criteria, Approval Boundary, Source, Tests และผลที่ผู้ใช้รายงานของ WP/Phase ปัจจุบันให้ชัดเจน
   - ใช้ Source/Tests เป็นหลักฐานการ Implement, ใช้ผลจากผู้ใช้เป็นหลักฐาน Compile/Runtime และถือว่า Docs/Memory อาจล้าสมัยได้

2. **กำหนดชุดเอกสารที่ได้รับผลกระทบ**
   - ตรวจ `PROJECT_STATUS.md` และ `.serena/memories/workflow/current-phase.md` ทุกครั้ง
   - ตรวจ Roadmap, README/Index, Architecture, Testing Guide/Inventory, Phase Note ปัจจุบัน และ ADR ที่เกี่ยวข้อง
   - หากเปลี่ยน Workflow ให้ตรวจ Repository-wide Workflow และ Agent Instructions ด้วย
   - แก้เฉพาะเอกสารที่ได้รับผลกระทบ แต่ต้องอ่านเอกสารที่เกี่ยวข้องมากพอเพื่อค้นหาความขัดแย้งข้ามไฟล์

3. **ตรวจความสอดคล้องเชิงความหมาย**
   - **Current Status:** สถานะ WP, วันที่เสร็จ, Next Step, Blocker และ Approval Boundary ต้องตรงกันทุกแห่ง
   - **Implementation Snapshot เทียบกับ Source:** ทุกข้อความที่ระบุว่ามี/ไม่มี Component ต้องตรงกับ Source ปัจจุบัน และแยก Module ที่ Implement แล้วออกจาก Production Integration ที่ยังไม่มี
   - **Tests และ Evidence:** Test Inventory/จำนวน Test ต้องตรงกับไฟล์และ Test Cases จริง แยก Static Review, User-reported Compile/Runtime และ Tests ที่ยังไม่ได้รัน ห้ามยกระดับหลักฐาน
   - **Architecture และ Contracts:** ขอบเขต, Diagram และ API Description ต้องตรงกับ Source และ Contract ที่อนุมัติแล้ว ห้ามเขียนแผนในอนาคตเสมือน Implement แล้ว
   - **Decisions และ History:** รักษา ADR และประวัติการตัดสินใจ ข้อความเก่าที่ถูกต้องในอดีตต้องระบุวันที่/บริบท และชี้ไปยังสถานะปัจจุบันเมื่ออาจทำให้เข้าใจผิด
   - **Authorization และ Safety:** Next Step ต้องไม่สื่อว่าได้รับอนุญาตให้ข้าม WP Boundary, ส่ง Trade Request, แตะต้อง Position ที่ไม่ใช่ Test หรือทำ Live Trading หากยังไม่มี Explicit Approval ที่จำเป็น

4. **ค้นหาข้อความล้าสมัยหรือขัดแย้ง**
   - ค้นหาแนวคิดที่เปลี่ยนและข้อความเดิมที่ทราบว่าอาจล้าสมัยใน `PROJECT_STATUS.md`, `Docs/`, `AGENTS.md` และ `.serena/memories/` ที่เกี่ยวข้อง
   - ค้นหาทั้งข้อความเชิงบวกและเชิงปฏิเสธ เช่น “มี Adapter แล้ว” และ “ยังไม่มี Adapter”, ข้อความรอ Compile/Run, สถานะ WP เก่า, จำนวน Test ที่ไม่ตรง และ Next Step ที่ล้าสมัย
   - ตรวจผลการค้นหาทีละจุด ห้ามลบ Historical Record โดยไม่พิจารณา หากถูกต้องในอดีตให้ระบุช่วงเวลา/บริบทและลิงก์ไปยังสถานะปัจจุบัน
   - บันทึก Search Terms/พื้นที่ที่ตรวจใน Completion Report

5. **ตรวจสอบขั้นสุดท้าย**
   - อ่าน Diff ทั้งหมด ไม่ใช่เฉพาะ Hunk ที่แก้ และยืนยันว่าไฟล์ที่เปลี่ยนทุกไฟล์อยู่ใน Scope
   - รัน `git diff --check`
   - ตรวจ Local Markdown Links ในเอกสารที่เปลี่ยนและเอกสารที่เกี่ยวข้อง
   - ตรวจ Test Inventory เทียบกับไฟล์จริงใน Test Directory เมื่อมีการเพิ่ม/ลบ/เปลี่ยนชื่อ Test
   - ตรวจ `git status --short --untracked-files=all` อีกครั้ง และรายงานไฟล์ Modified/Untracked ทั้งหมด
   - ห้าม Commit/Push เว้นแต่ผู้ใช้สั่งอย่างชัดเจน

## เกณฑ์ผ่าน

จะประกาศว่า WP/Phase ผ่านด้านเอกสารได้เมื่อ:
- ไม่มีความขัดแย้งที่ยังไม่ได้แก้ระหว่าง Current Status, Source, Tests และ Evidence
- Historical Wording ที่ยังคงไว้มีวันที่/บริบทชัดเจน
- แยก Implemented, User-verified, Agreed-not-implemented และ Open ออกจากกันได้
- Next Step ที่แน่นอนและ Approval ที่จำเป็นระบุชัดเจนและสอดคล้องกัน
- Diff, Markdown Links และ Inventory Checks ที่เกี่ยวข้องผ่าน หรือมีการบันทึกข้อจำกัดอย่างชัดเจน

หากข้อใดไม่ผ่าน ให้คง WP/Phase ไว้ในสถานะยังไม่สมบูรณ์ หรือรายงาน Documentation Task ว่ายังไม่เสร็จ ห้ามอ้างว่าผ่าน Gate

## รูปแบบ Completion Report

รายงานเอกสารที่ตรวจ/แก้ไข, ประเด็นเชิงความหมายและ Stale-claim Searches ที่ตรวจ, หลักฐาน Source/Test ที่ใช้, ผล Diff/Link/Inventory Checks, ข้อขัดแย้งหรือข้อจำกัดที่เหลือ, สถานะ Working Tree ล่าสุด และ Next Step พร้อม Approval ที่ต้องได้รับ
