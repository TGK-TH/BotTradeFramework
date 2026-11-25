# WP-05C — Test Plan

**สถานะ: APPROVED สำหรับ Design/Scope 2026-11-25 — Implementation ยัง NOT AUTHORIZED**

## 1. Preconditions

- WP-05A และ WP-05B ผ่าน Dependency Gates
- Snapshot Acquisition และ Reconciliation แยกเป็น Testable Ports
- ใช้ Fake Position Records; ห้ามอ่าน/แก้ไข Account จริงใน Unit Tests
- ไม่มี Trade Request

## 2. Test Cases

| ID | Scenario | Expected Result |
|---|---|---|
| C-01 | Full Scan สำเร็จและสอง Scan ตรงกัน | Snapshot ถูกยอมรับ |
| C-02 | Position Enumeration / Ticket Selection / Property Read ล้มเหลว | Snapshot Invalid; ไม่มี Reducer Mutation |
| C-03 | สอง Scan ไม่ตรงกัน | Retry/Reject; ไม่มี State Mutation |
| C-04 | Foreign Symbol หรือ Magic | ไม่ถูก Adopt/Map/Update |
| C-05 | Owned Position ตรงกับ Mapping ด้วย Position Identifier | Mapping ถูกยืนยัน; Ticket/Volume ตรง |
| C-06 | Position Ticket เปลี่ยนแต่ Identifier เดิม | Refresh Ticket; ไม่สร้าง Position Lifecycle ใหม่ |
| C-07 | Volume ลดลงแต่ยังมากกว่าศูนย์ | Partial Close Update; Mapping/ACTIVE คงอยู่ |
| C-08 | Volume เท่าเดิม | No-op เว้นแต่ Ticket เปลี่ยน |
| C-09 | Volume เพิ่มขึ้นสำหรับ Identifier เดิม | Fail Closed; ไม่เขียน Record |
| C-10 | Mapped Identifier หายจาก Complete/Stable Snapshot | Durable Reason-free Full Close หนึ่งครั้ง โดยคำนวณ READY/WAIT_ACTIVATION จาก Current executable-side quote (BUY=Ask, SELL=Bid) ณ เวลา Consume |
| C-11 | Snapshot เดิมถูกประมวลผลซ้ำ | ไม่มี Close Record ซ้ำ |
| C-12 | Owned Live Position ไม่มี Mapping/Valid Unresolved Request | Orphan; Fail Closed; ไม่เดา Level |
| C-13 | Mapping หายจาก Snapshot ที่ไม่ Complete | ห้าม Full Close |
| C-14 | Journal Append/Flush Failure ระหว่าง Partial/Full Close | ไม่เกิด Partial Reducer/Coordinator Mutation |
| C-15 | Full Close แล้ว Level เดิมได้รับ Position Identifier ใหม่ | Observation เก่าห้ามกระทบ Mapping ใหม่ |
| C-16 | Entry Request unresolved พร้อม Position/Deal evidence ที่ยังไม่ครบ | คง unresolved; ห้าม ACTIVE จน Mapping ยืนยัน |
| C-17 | Stable Snapshot ถูก Queue ไว้ แต่มี Entry/Mapping transition ใหม่ก่อน Consume | ปฏิเสธ stale Snapshot; ไม่มี Mutation จาก Observation เก่า |

## 3. Regression

- Snapshot Adapter Test EA
- Reconciliation Policy/Reducer Adapter Test EA
- Reducer + Snapshot Storage + Runtime Coordinator Tests
- Latest no-trade Grid Regression suite
- แยก Demo Trade Integration ออกและต้องขออนุมัติ Safety Gate ใหม่หากจะทำ

## 4. Safety

- Unit Tests ใช้ Fake Ports/Data เท่านั้น
- ไม่มี `CTrade`, `OrderSend`, `PositionClose` หรือ Trade Request
- ไม่มี Live/Demo Account mutation
- Snapshot acquisition failure ต้องไม่ถูกแปลงเป็น Position Count = 0

## 5. Evidence

ผู้ใช้รายงาน MetaEditor Compile/Run Results; Freebuff Compile ทุก Consumer ที่ได้รับผลกระทบให้ 0 errors / 0 warnings
