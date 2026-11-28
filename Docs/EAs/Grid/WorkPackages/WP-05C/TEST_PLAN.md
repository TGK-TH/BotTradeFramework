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

---

## 5. Technical Test Addendum (CTO Preparation — 2026-11-27)

### 5.1 Test EAs and Ports

- `test_grid_open_position_snapshot.mq5`: Fake Position Snapshot Port; no Account Position API.
- `test_grid_open_position_reconciliation.mq5`: Fake snapshot + fake journal + fake quote; no Trade API.
- Extend `test_grid_entry_mapping_reducer.mq5`: batch replay, malformed batch, all-or-nothing state, deal association projection.
- Extend `test_grid_entry_mapping_snapshot.mq5`: one-record batch durability, replay after restart, append/flush failure, journal rotation compatibility.
- Extend `test_grid_runtime_restoration.mq5` or `test_grid_level_runtime_coordinator.mq5`: explicit Gate release, mismatch/failure keeps Gate closed, quote baseline, no Candidate during release.

### 5.2 Required assertions by existing case

| Case | Additional assertions |
|---|---|
| C-01 | Both scans enumerate identical account totals; Owned set comparison ignores enumeration order; accepted token includes base sequence and generation |
| C-02 | Fail first/last enumeration index, zero ticket, failed selection, failed Identifier/Ticket/Symbol/Magic/Volume getter; whole snapshot invalid |
| C-03 | Change total, add/remove position, change identifier/ticket/symbol/magic/volume between scans; bounded retry exhausted => no accepted token |
| C-04 | Complete scan includes foreign Symbol, foreign Magic, manual Magic and another instance; none enter the Owned projection |
| C-05 | Match by decimal Position Identifier; mapping target comes only from Reducer projection |
| C-06 | Same Identifier/new Ticket updates only Ticket metadata; Identifier remains canonical |
| C-07 | Lower Volume + same/different Ticket emits one metadata update; Mapping and ACTIVE remain |
| C-08 | Same Volume/Ticket produces no journal record; same Volume/new Ticket emits one metadata update |
| C-09 | Volume increase, duplicate Identifier, duplicate Ticket or invalid/non-finite/non-positive volume rejects the whole batch |
| C-10 | Multiple missing mappings produce one atomic batch; BUY uses Ask and SELL uses Bid at Consume time; boundary cases around Level use existing WP-05A.2 state rule |
| C-11 | Same token cannot be consumed twice; equivalent fresh snapshot with unchanged reducer state is no-op; no duplicate close record |
| C-12 | Unmapped Owned Position with no matching durable Deal Association is Orphan; matching unresolved Request evidence remains unresolved and does not activate target |
| C-13 | Incomplete/unstable snapshot cannot generate a close even when the mapped Identifier is absent from the partial data |
| C-14 | Inject journal append/write/flush failure for a batch containing both metadata and full-close events; Reducer sequence/projection and Coordinator state/Gate remain unchanged |
| C-15 | After Full Close and a later new mapping for same target but different Identifier, old snapshot/token is rejected by generation/base sequence and cannot affect new mapping |
| C-16 | Unresolved Request with no position, partial deal evidence, or matching position/deal evidence remains unresolved until existing Entry Mapping pipeline confirms Mapping; no ACTIVE from snapshot alone |
| C-17 | Advance Reducer sequence after acquisition but before Consume; reject stale token before any append/apply/coordinator mutation |

### 5.3 Batch Atomicity / Replay Contract

- Reconciliation diff must be validated completely before persistence.
- All updates caused by one accepted snapshot are persisted in one lifecycle journal record.
- Replay of a valid batch applies every sub-event in deterministic order.
- Replay of malformed/conflicting batch fails the record and enters existing Recovery Error behavior; no prefix of the batch may remain applied.
- A successful append followed by an unexpected in-memory apply failure is Recovery Required; do not release Coordinator Gate.
- No-op batch has no journal record and does not increment sequence.

### 5.4 Compile / Runtime Evidence

- Compile every direct/transitive consumer of changed headers to `0 errors, 0 warnings`.
- Implementer does not run MT5 tests. Product Owner runs the new two EAs, affected existing Reducer/Storage/Coordinator/Restoration tests, and the complete latest no-trade Grid Regression suite.
- No Trade Request, Demo/Live account mutation or production `OnTradeTransaction` integration is permitted.
