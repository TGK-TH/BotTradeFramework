# Grid Level Engine — Design Specification (Approved)

อัปเดตล่าสุด: 2026-11-04

## สถานะ

**Design Agreed — Round 1 Source/Test prepared; MetaEditor Compile and Runtime validation pending user run.**

ผู้ใช้ยืนยัน Design และกติกาทั้ง 5 ประเด็นแล้วเมื่อ 2026-11-04 เอกสารนี้เป็นข้อกำหนดสำหรับ Implementation และ Test Cases รอบถัดไป ไม่ใช่หลักฐานว่า Source Code ปัจจุบันรองรับพฤติกรรมเหล่านี้แล้ว

## เป้าหมายและขอบเขต

Grid Level Engine เป็น Pure Logic สำหรับ:
- สร้าง Anchor Level และ Grid Levels จาก Fill Price, Grid Step และ Bounds
- กำหนด/ปรับ State ของแต่ละ Level ตาม Current Price และเหตุการณ์ Position
- ตรวจจับการ Activate, Retrace และ Re-entry
- เลือก Entry Candidate ได้ไม่เกินหนึ่ง Level ต่อ Price Check
- ส่งข้อมูล Candidate/Transition ให้ Runtime หรือ Execution layer โดยไม่เรียก Trade API

ไม่รวมในรอบ Engine:
- ส่งคำสั่งเปิด/ปิด Position ผ่าน `CTrade`
- Production EA `OnTick()` / `OnTimer()` integration
- การจัดการ TP/SL จริงหรือการอ่าน Deal History เอง
- Live/Demo trading integration

Order Execution และ Reconciliation เป็นหน้าที่ของ Runtime/Execution layer; Engine ต้องรองรับผลลัพธ์และ State transitions ที่ชั้นนั้นรายงานกลับมา

## 1. ประเภท Level และการคำนวณราคา

### Anchor Level
- ใช้ราคา Fill จริงของ Initial Position เป็น Anchor
- เป็น Special Level แยกจาก Grid Levels ปกติ
- มี State Machine และรองรับ Re-entry เช่นเดียวกับ Grid Level
- ไม่ถูกนับรวมใน `level_count`
- ห้ามสร้าง Grid Level ปกติซ้ำที่ราคา Anchor

### Grid Levels
- สร้างทั้งสองด้านของ Anchor (Two-sided Grid)
- BUY/SELL ไม่ได้จำกัด Level ไว้เฉพาะด้านใดด้านหนึ่งของ Anchor
- ระดับราคาคำนวณจาก Anchor และ Grid Step โดยไม่เลื่อน Level ไปชิด Bounds
- Bounds เป็น Hard Filter: Level ที่อยู่นอกช่วง [Lower Bound, Upper Bound] ไม่ถูกสร้างเป็น Level ที่ใช้งานได้
- `level_count` หมายถึงจำนวน Grid Levels ปกติที่อยู่ใน Bounds ทั้งหมด ไม่รวม Anchor
- หาก Bounds ไม่ตรงกับ Step ให้เก็บเฉพาะระดับที่คำนวณจาก Anchor + Step ซึ่งอยู่ใน Bounds

ตัวอย่าง: Anchor=4000, Step=5, Lower=3992, Upper=4012 จะมี Grid Levels 3995, 4005, 4010 เท่านั้น (Anchor 4000 แยกต่างหาก)

## 2. State Model

ใช้ 4 States:

| State | ความหมาย |
|---|---|
| `WAIT_ACTIVATION` | Level อยู่ด้านที่ยังไม่พร้อมเข้า รอราคาเคลื่อนผ่านเพื่อ Activate |
| `READY` | Level พร้อมเป็น Entry Candidate เมื่อราคา Retrace กลับมา |
| `ACTIVE` | มี Position ของ Level นี้เปิดอยู่ |
| `WAIT_RETURN` | Position ปิดด้วย TP แล้ว รอราคากลับมาที่ Entry Level เพื่อ Re-entry |

State ของ Level ที่ไม่มี Position อิง Current Price ไม่ได้อิงว่า Level อยู่เหนือ/ใต้ Anchor และไม่อิงเพียงประวัติว่าเคยเปิด Position หรือไม่

### Initial State

ใช้ราคาที่เกี่ยวข้องกับ Mode:
- BUY ใช้ Ask
- SELL ใช้ Bid

BUY:
- Level เหนือหรือเท่ากับ Current Ask เริ่มเป็น `WAIT_ACTIVATION`
- Level ใต้ Current Ask เริ่มเป็น `READY`
- Anchor เริ่มเป็น `ACTIVE` เมื่อมี Initial Position ที่ Fill Price แล้ว

SELL (กลับด้าน):
- Level ใต้หรือเท่ากับ Current Bid เริ่มเป็น `WAIT_ACTIVATION`
- Level เหนือ Current Bid เริ่มเป็น `READY`
- Anchor เริ่มเป็น `ACTIVE` เมื่อมี Initial Position ที่ Fill Price แล้ว

## 3. Price Direction และ State Transitions

### BUY Mode (ใช้ Ask)

- ราคาเคลื่อนขึ้นผ่าน `WAIT_ACTIVATION` -> `READY`
- ราคาเคลื่อนลงผ่าน `READY` -> เป็น Entry Candidate
- เมื่อ Order เปิดสำเร็จ -> `ACTIVE`
- เมื่อ Position ปิด ให้พิจารณา Current Ask ก่อน: หาก Level อยู่เหนือหรือเท่ากับ Ask -> `WAIT_ACTIVATION`; หาก Level อยู่ใต้ Ask และปิดด้วย TP -> `WAIT_RETURN`; หากปิดด้วยเหตุผลอื่น -> `READY`
- เมื่อราคากลับลงมาถึง Level ที่เป็น `WAIT_RETURN` -> ส่ง Re-entry Candidate; เมื่อเปิดสำเร็จ -> `ACTIVE`
- หาก Position ปิดด้วยเหตุผลอื่นที่ไม่ใช่ TP (เช่น SL หรือ Manual Close):
  - Level อยู่เหนือ Current Ask -> `WAIT_ACTIVATION`
  - Level อยู่ใต้ Current Ask -> `READY`

### SELL Mode (ใช้ Bid; กลับด้านจาก BUY)

- ราคาเคลื่อนลงผ่าน `WAIT_ACTIVATION` -> `READY`
- ราคาเคลื่อนขึ้นผ่าน `READY` -> เป็น Entry Candidate
- เมื่อ Order เปิดสำเร็จ -> `ACTIVE`
- เมื่อ Position ปิด ให้พิจารณา Current Bid ก่อน: หาก Level อยู่ใต้หรือเท่ากับ Bid -> `WAIT_ACTIVATION`; หาก Level อยู่เหนือ Bid และปิดด้วย TP -> `WAIT_RETURN`; หากปิดด้วยเหตุผลอื่น -> `READY`
- เมื่อราคากลับขึ้นมาถึง Level ที่เป็น `WAIT_RETURN` -> ส่ง Re-entry Candidate; เมื่อเปิดสำเร็จ -> `ACTIVE`
- หาก Position ปิดด้วยเหตุผลอื่นที่ไม่ใช่ TP:
  - Level อยู่ใต้ Current Bid -> `WAIT_ACTIVATION`
  - Level อยู่เหนือ Current Bid -> `READY`

### Position ownership and ACTIVE

- `ACTIVE` คงอยู่ตราบใดที่ Position ของ Level นั้นยังเปิดอยู่ ไม่ว่า Current Price จะเคลื่อนผ่าน Level ไปมาอย่างไร
- Level จะออกจาก `ACTIVE` เมื่อ Execution/Runtime ยืนยันว่า Position ปิดแล้ว และแจ้งเหตุผลการปิดให้ Engine
- การส่ง Order หรือการได้รับ Accepted retcode เพียงอย่างเดียวไม่ถือว่า Position เปิดสำเร็จ ต้องยืนยันด้วย Position Reconciliation ก่อนเปลี่ยนเป็น `ACTIVE`

## 4. Candidate Selection

เลือกจาก Level ที่ถูกข้าม/แตะตามทิศทาง Entry และมี State ที่อนุญาตให้เข้า (ทั้ง `READY` และ `WAIT_RETURN`):

- BUY: หากมีหลาย Candidate ใน Price Check เดียวกัน เลือกราคาต่ำที่สุด
- SELL: หากมีหลาย Candidate ใน Price Check เดียวกัน เลือกราคาสูงที่สุด
- ไม่สนใจว่า Candidate อยู่เหนือหรือต่ำกว่า Anchor
- หนึ่ง Price Check เลือกได้ไม่เกินหนึ่ง Candidate
- Anchor เป็น Candidate ได้ตาม State/เงื่อนไขเดียวกับ Grid Level
- `ACTIVE` ไม่มีสิทธิ์เป็น Candidate

เมื่อเลือก Candidate แล้ว Order Execution/Reconciliation เป็นผู้พยายามเปิด Order และยืนยันผลจริง

## 5. Unselected Levels และ Reconciliation

### Level ที่ไม่ได้รับเลือก

เมื่อราคาข้ามหลาย Level แต่เลือกได้เพียงหนึ่ง:
- BUY: Level ที่ไม่ได้รับเลือกและปัจจุบันอยู่เหนือ Ask เปลี่ยนจาก `READY` หรือ `WAIT_RETURN` เป็น `WAIT_ACTIVATION`
- SELL: Level ที่ไม่ได้รับเลือกและปัจจุบันอยู่ใต้ Bid เปลี่ยนจาก `READY` หรือ `WAIT_RETURN` เป็น `WAIT_ACTIVATION`
- `ACTIVE` ต้องคงเดิมเสมอ

### Order Retry และ Candidate ที่ดีกว่า

- เมื่อราคาแตะ Candidate ให้ Runtime/Execution พยายามเปิด Order และใช้ Reconciliation ยืนยันผล
- หาก Candidate เดิมยังเปิดไม่สำเร็จ แต่ราคาเคลื่อนไปถึง Candidate ที่ดีกว่า ให้ Candidate ใหม่เข้ามาแทนได้โดยไม่ต้องรอ Candidate เดิม
- BUY Candidate ที่ดีกว่าคือราคาต่ำกว่า; SELL Candidate ที่ดีกว่าคือราคาสูงกว่า
- หากระหว่าง Retry ราคาผ่าน Level เดิมไปจน Level นั้นอยู่ผิดด้านของ Current Price และยังไม่มี Position ให้ปรับเป็น `WAIT_ACTIVATION` ตามกฎ Unselected Levels
- Engine ไม่ส่งคำสั่ง Trade เอง และไม่ตีความ Accepted request ว่าเปิด Position สำเร็จ

## 6. Position Close Outcomes

เมื่อ Runtime/Reconciliation ยืนยันว่า Position ปิดแล้ว:
- ใช้ Current Price ตัดสินก่อนเสมอ: หาก Level อยู่ผิดด้านของตลาด (BUY: Level >= Ask; SELL: Level <= Bid) ให้ `WAIT_ACTIVATION` ไม่ว่าจะปิดด้วยเหตุผลใด
- หาก Level ยังอยู่ด้าน Re-entry ของตลาด (BUY: Level < Ask; SELL: Level > Bid): ปิดด้วย TP ให้ `WAIT_RETURN`; ปิดด้วยเหตุผลอื่น (SL, Manual Close และอื่น ๆ) ให้ `READY`
- กรณีปิด Position หลายเหตุผล/หลาย Deal ต้องให้ Integration layer ระบุผลปิดของ Position/Level อย่างชัดเจนก่อนแจ้ง Engine

## 7. Re-entry และ Anchor

- Anchor Level ใช้ State Machine เดียวกับ Grid Levels
- Initial Position ที่ Fill Price ทำให้ Anchor เป็น `ACTIVE`
- เมื่อ Anchor Position ปิด TP -> `WAIT_RETURN`
- เมื่อราคากลับถึง Anchor -> ส่ง Re-entry Candidate; เมื่อเปิดสำเร็จ -> `ACTIVE`
- หาก Anchor Position ปิดด้วยเหตุผลอื่น -> ใช้ Current Price ตัดสิน `WAIT_ACTIVATION` หรือ `READY`
- Anchor ไม่ถูกนับในจำนวน Grid Levels และไม่มี Grid Level ปกติซ้ำที่ราคา Anchor

## 8. Test Cases ที่ต้องมี

Test EA: `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5`

### Calculation / Bounds
1. สร้าง BUY และ SELL Two-sided Levels ทั้งเหนือและใต้ Anchor
2. Anchor ไม่ปรากฏซ้ำใน Grid Levels และไม่ถูกรวมใน `level_count`
3. คำนวณราคาจาก Anchor + Step แบบคงที่ ไม่เลื่อนตาม Bounds
4. Bounds ตรงกับ Level: รวม Level ที่ Lower/Upper Bound
5. Bounds ไม่ตรงกับ Step: Anchor=4000, Step=5, Bounds=3992..4012 -> ได้ 3995, 4005, 4010
6. Level นอก Bounds ไม่ถูกสร้าง/เลือก
7. ปฏิเสธ Anchor, Step, Bounds และจำนวน Level ที่ไม่ถูกต้อง

### Initial State
8. BUY: เหนือ Ask = WAIT_ACTIVATION; ใต้ Ask = READY
9. SELL: ใต้ Bid = WAIT_ACTIVATION; เหนือ Bid = READY
10. Anchor ที่มี Initial Position = ACTIVE

### Activation / Entry
11. BUY: ราคา Ask ขึ้นผ่าน WAIT_ACTIVATION -> READY
12. BUY: ราคา Ask ลงผ่าน READY -> Candidate
13. SELL: ราคา Bid ลงผ่าน WAIT_ACTIVATION -> READY
14. SELL: ราคา Bid ขึ้นผ่าน READY -> Candidate
15. การเคลื่อนที่ผิดทิศทางไม่ Activate/ไม่สร้าง Candidate
16. ทดสอบ touch, exact equality และ gap/crossing ของราคาอย่างชัดเจน

### Candidate Selection
17. BUY ข้ามหลาย READY Levels -> เลือกราคาต่ำที่สุด
18. SELL ข้ามหลาย READY Levels -> เลือกราคาสูงที่สุด
19. Candidate อยู่คนละด้านของ Anchor ได้ และ Anchor เป็น Candidate ได้
20. รวม READY และ WAIT_RETURN ใน Candidate selection
21. มี Candidate เดียวให้เลือก Candidate นั้น
22. ไม่มี Candidate ให้คืนผล no-candidate
23. หนึ่ง Price Check ต้องไม่คืนมากกว่าหนึ่ง Candidate
24. ACTIVE ไม่ถูกเลือก

### Unselected Levels / Reconciliation
25. BUY: READY ที่ถูกข้ามแต่ไม่ถูกเลือกและอยู่เหนือ Ask -> WAIT_ACTIVATION
26. SELL: READY ที่ถูกข้ามแต่ไม่ถูกเลือกและอยู่ใต้ Bid -> WAIT_ACTIVATION
27. กฎเดียวกันใช้กับ WAIT_RETURN ที่ถูกข้ามแต่ไม่ถูกเลือก
28. ACTIVE ที่ราคาเคลื่อนผ่านต้องคง ACTIVE
29. Candidate เดิมเปิดไม่สำเร็จและมี Candidate ที่ดีกว่า -> Candidate ใหม่แทนได้
30. Candidate เดิมที่ไม่มี Position และอยู่ผิดด้านของ Current Price -> WAIT_ACTIVATION
31. Order accepted แต่ยังไม่พบ Position -> ยังไม่เปลี่ยนเป็น ACTIVE
32. Reconciliation ยืนยัน Position เปิดแล้ว -> ACTIVE

### Position Close / Re-entry
33. ACTIVE ปิดด้วย TP -> WAIT_RETURN
34. BUY WAIT_RETURN ราคากลับลงมาถึง Level -> Re-entry Candidate
35. SELL WAIT_RETURN ราคากลับขึ้นมาถึง Level -> Re-entry Candidate
36. Re-entry เปิดสำเร็จหลัง Reconciliation -> ACTIVE
37. ปิดด้วย SL -> เลือก WAIT_ACTIVATION/READY ตาม Current Price
38. ปิดด้วย Manual Close -> เลือก WAIT_ACTIVATION/READY ตาม Current Price
39. ปิดด้วยเหตุผลอื่นที่ไม่ใช่ TP -> ใช้กฎ Current Price เดียวกัน
40. Anchor Position ปิด TP และ Re-entry ได้
41. Anchor Position ปิดด้วยเหตุผลอื่นและจัด State ตาม Current Price
42. Position ของ Level หนึ่งปิด/เปลี่ยน State ต้องไม่กระทบ State ของ Level อื่น

## 9. ข้อจำกัดที่ยังต้องกำหนดใน Test/Implementation Detail

ข้อกำหนดด้านบนล็อก Trading Logic แล้ว แต่ Implementation/Test ต้องระบุ behavior เชิงขอบเพิ่มเติมอย่างชัดเจน:
- เมื่อราคาเท่ากับ Level พอดี จะถือว่า touch/ผ่านใน Price Check ใด และป้องกันการ trigger ซ้ำอย่างไร
- วิธีส่ง/ระบุ Candidate ที่กำลัง Retry และวิธี reconcile หลาย Candidate เมื่อราคาเคลื่อนเร็ว
- การจัดการ Partial Close หรือหลาย Position ต่อ Level (หาก API ปัจจุบันอนุญาต) ต้องรักษา ACTIVE จน Position ของ Level นั้นหมดจริง
- การ Restore State ของ Anchor/Levels หลัง Restart จะเชื่อมกับ Persistence ใน Phase แยก ไม่ใช่ส่วนของ Pure Engine รอบนี้

ประเด็นเหล่านี้ต้องถูกระบุใน Test Cases ก่อน implementation ที่เกี่ยวข้อง ไม่ควรสมมติพฤติกรรมเอง

## 10. Validation Status

- Design: ผู้ใช้ยืนยันครบ 5 รายการเรื่อง Bounds, Unselected Levels, Retry/Candidate replacement, Non-TP close และ Anchor Re-entry เมื่อ 2026-11-04
- Source: ยังไม่ปรับ `GridLevelEngine.mqh` หรือ Test EA ให้ตรง Design ฉบับนี้
- Compile/Runtime: ยังไม่ได้ทดสอบ; ผู้ใช้แจ้งว่ายังไม่ได้ Compile เพราะกำลัง Review Design
- Regression: Baseline 10 Grid Tests ผู้ใช้รายงาน PASS เมื่อ 2026-11-03 ก่อนเพิ่ม Grid Level Engine prototype
- ขั้นตอนถัดไป: Review/ล็อก Edge Cases และ Test Cases จากนั้นจึงเริ่ม Test-first implementation เมื่อผู้ใช้อนุมัติ
