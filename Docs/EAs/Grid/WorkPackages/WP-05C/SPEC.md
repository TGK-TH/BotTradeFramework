# WP-05C — Open Positions Reconciliation

**สถานะ: APPROVED — Product Owner อนุมัติ Design/Scope 2026-11-25**
**Implementation: NOT AUTHORIZED**  
**Dependencies:** WP-05A และ WP-05B

## 1. วัตถุประสงค์

สร้าง Authoritative Open Positions Reconciliation ที่แปลง Complete/Stable Live Position Snapshot เป็น Durable Position Mapping / Volume / Ticket / Full Close Facts ให้ Canonical Reducer และ Runtime Coordinator โดยไม่สร้าง Mapping หรือ State Machine ซ้ำ

## 2. Source Inspection Findings

- `CTGKGridPositionReconciler` ปัจจุบันเป็น Reset/Close-confirmation component; `STGKGridPositionRecord` เก็บเพียง Ticket, Symbol และ Magic Number
- `CountLiveOwnedPositions()` คืนค่าเป็น Count และอ่าน Symbol/Magic เท่านั้น; ไม่มี Position Identifier, Volume หรือ Complete Position Records สำหรับ Position Lifecycle Reconciliation
- ดังนั้น Component เดิมไม่ใช่ Authoritative WP-05C Snapshot Adapter โดยตรง; สามารถ reuse เฉพาะ Ownership Predicate/แนวทาง Fresh Scan ได้ แต่ต้องไม่ทำให้ Reset Close semantics เปลี่ยน
- WP-05C ต้องมี Full Snapshot DTO/Port ที่เก็บ Position Identifier, Ticket, Symbol, Magic และ Volume พร้อม Failure/Completeness semantics

## 3. In Scope

- แยก Live Position Snapshot Acquisition ออกจาก Pure Reconciliation Policy ผ่าน Testable Port/Interface
- Enumerate Account Positions ทั้งหมด; หาก Enumeration, Ticket Selection หรือ Required Property Read ใดล้มเหลว ให้ Snapshot ทั้งชุด Invalid
- Capture Position Identifier, Position Ticket, Symbol, Magic Number และ Volume
- พิสูจน์ Snapshot Completeness/Stability ก่อน Mutation; ใช้สอง Full Scans ที่ Position Set และ Relevant Fields ตรงกัน หรือ Contract การ Retry ที่เทียบเท่าและพิสูจน์ได้
- Acquire และ Consume Accepted Snapshot ภายใน Serialized EA Event เดียวกัน; ห้าม Queue หรือ Apply Observation ที่ stale หลัง Reconciliation/Entry Confirmation รอบใหม่
- สำหรับ Full Close ต้อง Validate Current executable-side quote ณ เวลาที่ Consume Stable Snapshot (BUY=Ask, SELL=Bid) และคำนวณ Post-close State ตาม WP-05A.2
- Filter exact Symbol + Instance Magic หลัง Full Account Scan ผ่านเท่านั้น
- Match Durable Mapping ด้วย Position Identifier; Ticket เป็น Refreshable Operational Handle
- Volume ลดลง: Partial Close / Position Metadata Update; Mapping และ ACTIVE คงอยู่เมื่อ Volume ยังมากกว่าศูนย์
- Volume เท่าเดิม: ไม่มี State Mutation เว้นแต่ Ticket เปลี่ยน
- Volume เพิ่มขึ้นสำหรับ Hedging Position Identifier เดิม: Conflicting Evidence / Fail Closed
- Mapping ที่หายไปจาก Complete/Stable Snapshot: Reason-free Full Close ผ่าน Durable Transition ของ WP-05A.2
- Owned Live Position ที่ไม่มี Mapping หรือ Valid Unresolved Entry Request: Orphan / Fail Closed
- ส่ง Validated Position Projection และผล Reconciliation ให้ Runtime Coordinator
- รักษา Entry Deal Association correlation pipeline เดิม; หากจำเป็นต้องอ่าน Deal History เพื่อ Entry Fill Correlation ให้จำกัดเฉพาะ Entry Deals เท่านั้น

## 4. Out of Scope

- Closing Deal History เพื่อยืนยัน Full Close
- TP/NON_TP, SL/Manual classification, Close Price หรือ Close Reason inference
- Production `OnTradeTransaction` Integration (WP-05D)
- Order Execution, Demo/Live Trading หรือ Trade Requests
- เปลี่ยน Entry Selection, Grid Geometry หรือ Trading Behavior

## 5. Approved Architecture Constraints

- Full Close เกิดจากการที่ Position Identifier ที่มี Durable Mapping หายไปจาก Complete/Stable Open Positions Snapshot
- ห้ามตีความ Scan Failure, Empty/Partial Scan หรือ Unstable Scan ว่าไม่มี Position
- Position Identifier เป็น Canonical Lifecycle Identity; Position Ticket เป็น Operational Handle
- Partial Close ไม่ลบ Mapping และไม่เปลี่ยน Anchor/Level ออกจาก ACTIVE ขณะที่ Volume ยังเหลือ
- Full Close เป็น Reason-free Atomic Durable Transition; Mapping Removal และ Anchor/Level State Update ต้องอยู่ใน Journal Transition เดียว
- State-based idempotency; ไม่เพิ่ม Processed Close Event Registry
- Entry Deal Association ที่มีอยู่ยังคงแยกจาก Closing Deal History
- Open Positions Snapshot ไม่สามารถสร้างประวัติ Position ที่เปิดและปิดทั้งหมดระหว่าง EA Offline หรือระหว่าง Observation กลับมาได้ และไม่ให้ Close Reason/Close Price/Partial-Close History; ข้อมูลเหล่านี้ไม่ใช่ Requirement ของ Grid State Contract ที่อนุมัติแล้ว

## 6. Acceptance Criteria

- [ ] Failed/Incomplete/Unstable Snapshot ไม่มี Durable State Mutation
- [ ] Foreign/Manual/Other Instance Positions ไม่ถูก Adopt หรือแก้ไข
- [ ] Identifier เป็น Mapping Key; Ticket Refresh ไม่สร้าง Position Lifecycle ใหม่
- [ ] Partial Close ปรับ Volume/Ticket และคง ACTIVE
- [ ] Full Close ทำได้เมื่อ Position หายจาก Complete/Stable Snapshot เท่านั้น
- [ ] Full Close ใช้ Reason-free Durable Transition และไม่อ่าน Closing Deal History
- [ ] Full Close State ใช้ Current executable-side quote ณ เวลาที่ Consume Stable Snapshot; BUY ใช้ Ask, SELL ใช้ Bid; ห้ามใช้ Quote/Snapshot ที่ stale
- [ ] Orphan/Conflicting Evidence เข้า Fail Closed โดยไม่เดา Mapping
- [ ] Duplicate Snapshot/Reconciliation เป็น Idempotent
- [ ] Storage Append/Apply Failure ไม่เกิด Partial In-memory Transition
- [ ] Tests ใช้ Fake Position Snapshot/Ports และไม่มี Trade Request

## 7. Dependencies / Gate

ต้องใช้ Restore Contract จาก WP-05B และ Canonical Persistence Contract จาก WP-05A.2/WP-05A.3

การ Implement ต้องได้รับ Product Owner Approval แยกต่างหาก และต้องรัน Latest no-trade Grid Regression Baseline ก่อน Source Change
