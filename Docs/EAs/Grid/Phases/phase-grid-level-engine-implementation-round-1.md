# Grid Level Engine — Implementation Notes (Round 1)

อัปเดตล่าสุด: 2026-11-04

เอกสารนี้ต่อยอดจาก [Design Specification](phase-grid-level-engine-design.md) และบันทึกกติกา Edge Cases ที่ใช้กับ Pure Engine รอบแรก รวมถึงสถานะ Source/Test ปัจจุบัน

## Edge Contracts

### Exact Touch / Equality / Duplicate Prevention

ใช้ half-open crossing:
- BUY Activation: Previous Ask < Level และ Current Ask >= Level
- BUY Entry: Previous Ask > Level และ Current Ask <= Level
- SELL Activation: Previous Bid > Level และ Current Bid <= Level
- SELL Entry: Previous Bid < Level และ Current Bid >= Level

Current Price แตะ Level พอดีถือเป็น crossing ใน Price Check นั้น แต่ Price Check ถัดไปที่ราคาไม่เปลี่ยนจะไม่ Trigger ซ้ำ เพราะ Previous Price ต้องอยู่ฝั่งก่อน Level อย่างเคร่งครัด

หาก Initialize ขณะที่ Current Price เท่ากับ Level พอดี จะยังไม่ถือว่ามี crossing; BUY Level ที่เท่ากับ Ask เริ่ม WAIT_ACTIVATION และ SELL Level ที่เท่ากับ Bid เริ่ม WAIT_ACTIVATION ต้องเคลื่อนออกไปอีกด้านแล้วกลับมาข้ามใหม่

ใช้ Ask สำหรับ BUY และ Bid สำหรับ SELL

### Retry / Reconciliation Handoff

- Engine คืน Candidate ได้สูงสุดหนึ่งตัวต่อ Price Check และไม่เปลี่ยนเป็น ACTIVE เอง
- Execution layer ต้องป้องกันการส่งคำสั่งซ้ำสำหรับ Level ที่มีคำขอเปิด Order ค้างอยู่
- Accepted/Placed แต่ยังไม่พบ Position ถือว่ายัง unresolved; ห้ามตีความเป็น failed หรือส่งคำสั่งซ้ำสำหรับ Candidate เดิม
- Candidate ถือว่า failed/retryable เมื่อ request ถูกปฏิเสธ/ล้มเหลวชัดเจน หรือ Reconciliation ยืนยันว่าไม่มี Position และไม่มีคำขอค้างอยู่
- เมื่อ Candidate ก่อนหน้าล้มเหลวและราคาเคลื่อนไปถึง Level ที่ดีกว่า (BUY ราคาต่ำกว่า / SELL ราคาสูงกว่า) Execution layer ใช้ Candidate ใหม่ได้โดยไม่ต้อง retry Level เดิมก่อน
- หาก Candidate ใหม่เกิดขึ้นขณะคำขอก่อนหน้ายัง unresolved, Runtime/Execution ต้องเก็บ Candidate ที่ดีกว่าไว้และดำเนินการเมื่อคำขอก่อนหน้าถูก resolve; ห้ามทิ้ง event และห้ามส่งคำสั่งซ้อนโดยไม่ reconcile
- Candidate ที่เปิดไม่สำเร็จและ Level อยู่ผิดด้านของ Current Price ให้ Engine เปลี่ยนเป็น WAIT_ACTIVATION ผ่าน RecordEntryFailed()
- เปลี่ยนเป็น ACTIVE ได้เมื่อ Reconciliation ยืนยัน Position แล้วเท่านั้น ผ่าน RecordEntryConfirmed()

### Position Cardinality / Partial Close

- หนึ่ง logical Level มีได้ไม่เกินหนึ่ง logical open position ในเวลาเดียวกัน
- หากมี partial close แต่ยังมี Position volume เหลือ Level ต้องคง ACTIVE
- เรียก RecordPositionClosed() เฉพาะเมื่อ Reconciliation ยืนยันว่าไม่มี Position เหลือสำหรับ Level นั้น
- การ Mapping Position ticket/deal กับ Anchor หรือ Grid Level เป็นหน้าที่ Integration layer ไม่ใช่ Pure Engine

### Restart / Persistence

การ Restore Anchor State และ Grid Level States หลัง Restart เป็นงาน Persistence/Integration แยกต่างหาก Pure Engine ไม่อ่านหรือเขียน persistence เอง

## Round 1 Source Changes

- Caller supplies `level_count` as the total ordinary levels on both sides of Anchor (Anchor excluded); Engine independently calculates the expected count from Anchor, Step and hard Bounds and rejects a mismatch. Levels are stored in ascending price order.
- Bounds เป็น hard filter; ไม่เลื่อนระดับราคา
- Initial states อิง Current Ask/ Bid และ Anchor เริ่ม ACTIVE เพราะแทน Initial Position
- เพิ่ม WAIT_ACTIVATION โดย append enum value เพื่อรักษาค่า numeric เดิมของ READY, ACTIVE และ WAIT_RETURN
- GridPersistence enum validation รองรับ WAIT_ACTIVATION โดยไม่เปลี่ยนค่า enum เดิม
- UpdatePrice อัปเดต activation state และคืน Candidate สูงสุดหนึ่งตัว; BUY เลือกราคาต่ำสุด, SELL เลือกราคาสูงสุด
- รองรับ READY และ WAIT_RETURN เป็น Candidate; ACTIVE ไม่ถูกเลือก
- เพิ่ม RecordEntryConfirmed(), RecordEntryFailed() และ RecordPositionClosed() เพื่อรับผลจาก Execution/Reconciliation

## Test Changes

- test_grid_level_engine.mq5 ครอบคลุม Two-sided calculation, hard Bounds, initial states, activation, BUY/SELL best-price selection, unselected WAIT_RETURN transition, Anchor re-entry, TP/non-TP close state, entry failure, exact touch และ stationary-price duplicate prevention
- test_grid_persistence.mq5 เพิ่ม Save/Restore สำหรับ WAIT_ACTIVATION
- test_grid_types.mq5 เพิ่ม assertion ยืนยัน numeric enum value ของ WAIT_ACTIVATION = 3
- ยังต้อง Compile และ Run ใน MetaEditor/MT5 โดยผู้ใช้

## Validation

- `git diff --check` and lightweight delimiter checks: PASS
- MetaEditor compile: pending user run
- Grid Level Engine unit tests: pending user run
- Full Grid regression: pending user run
