# D-06-02 — Minimal Strategy Tester Probe / SPEC

อัปเดต: 2026-11-28

สถานะ: Product Owner อนุมัติให้จัดทำ Probe แล้ว; เอกสาร/ขอบเขตพร้อมส่ง Implementer; ยังไม่อนุญาตให้ Implementer สร้าง/แก้ Source หรือรัน Probe จนกว่าจะมีการมอบหมายและอนุมัติขั้นตอนถัดไปอย่างชัดเจน

## 1. วัตถุประสงค์

สร้าง EA ทดสอบเฉพาะกิจเพื่อเก็บหลักฐานจาก MT5 Strategy Tester จริง สำหรับ D-06-02 โดยไม่ผูกกับ Production Grid Runtime และไม่เปลี่ยน Contract หรือ Source ของ WP-06A/B/C

Probe ต้องตรวจสอบ:
- Transaction callbacks ที่เกิดจาก Market Entry Request หนึ่งครั้ง และลำดับที่ EA ได้รับ
- ความพร้อมอ่าน Deal History ทันทีภายใน `OnTradeTransaction` เทียบกับการอ่านภายหลัง
- การเลือก History Order ด้วย Order Ticket ที่ได้จาก `CTrade.ResultOrder()`
- การ Enumerate Deals ทั้งหมดในช่วง History ที่กำหนด และกรองด้วย `DEAL_ORDER == Order Ticket` เท่านั้น
- ความพร้อมของ Deal properties ที่ WP-06B ต้องใช้
- ความสัมพันธ์ระหว่าง Order, Deal และ Position Identifier
- จำนวน Deal / Partial Fill ที่เกิดขึ้นจริงภายใต้ execution configuration ที่ระบุ
- การสร้าง recovery projection ใหม่จาก persisted Order Ticket โดยไม่อาศัย RAM callback queue (จำกัดความหมายตามหัวข้อ Restart Limitation)

Probe เป็น diagnostic integration test เท่านั้น ไม่ใช่ Production Event Bridge และไม่ปิด D-06-02 โดยอัตโนมัติ

## 2. ขอบเขต

### In Scope

1. สร้าง EA ไฟล์เดียว:
   - `Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5`
2. ใช้ `CTrade` แบบ synchronous และ `SetTypeFillingBySymbol(_Symbol)` เพื่อให้เส้นทางส่งคำสั่งใกล้เคียง Entry CTrade Port ปัจจุบัน
3. ส่ง Market Request ได้สูงสุดหนึ่งครั้งต่อ Probe Session
4. บันทึก Request result: return value, retcode, Order Ticket, ResultDeal hint, result volume/price และเวลาที่ส่ง
5. มี `OnTradeTransaction` diagnostic handler เก็บ callback sequence และ field ที่เกี่ยวข้องลง bounded in-memory buffer
6. สำหรับ `TRADE_TRANSACTION_DEAL_ADD` ให้ทำ immediate single-Deal History select/property-read probe เพื่อบันทึกว่าอ่านได้หรือไม่ ณ เวลาที่ callback ทำงาน ห้าม enumerate History ทั้งชุดใน callback
7. ทำ serialized exact-order History scan นอก callback:
   - เลือก Order ด้วย `HistoryOrderSelect(order_ticket)`
   - อ่านและเก็บ Order setup time / properties ที่ต้องใช้
   - เรียก `HistorySelect(from, to)` ด้วย bounded interval รอบ Order setup time ถึงเวลาปัจจุบัน
   - Enumerate ด้วย `HistoryDealsTotal()` + `HistoryDealGetTicket(index)`
   - กรองทุก Deal ด้วย exact `DEAL_ORDER == order_ticket`
   - ห้ามใช้ Comment, ราคาใกล้เคียง, Magic อย่างเดียว หรือ time proximity เป็นตัวเชื่อมโยง Request
8. อ่าน Deal properties:
   - `DEAL_ORDER`
   - `DEAL_ENTRY`
   - `DEAL_TYPE`
   - `DEAL_SYMBOL`
   - `DEAL_MAGIC`
   - `DEAL_POSITION_ID`
   - `DEAL_VOLUME`
   - `DEAL_PRICE`
   - `DEAL_TIME` และ/หรือ `DEAL_TIME_MSC` หากรองรับใน Build ที่ทดสอบ
9. อ่าน Position snapshot โดยกรอง Symbol + Probe Magic แบบ exact และบันทึก:
   - `POSITION_IDENTIFIER`
   - `POSITION_TICKET`
   - `POSITION_VOLUME`
   - `POSITION_PRICE_OPEN`
10. เปรียบเทียบ ResultDeal hint กับชุด Deal ที่พบจาก exact-order scan; ResultDeal ไม่ใช่แหล่งข้อมูล Deal ทั้งหมด
11. Persist Order Ticket และข้อมูลขั้นต่ำที่จำเป็นเป็น decimal text ในไฟล์เฉพาะ Probe Session แล้วทดสอบ recovery routine โดยล้าง volatile callback state และโหลดข้อมูลกลับจากไฟล์ ก่อนเรียก exact-order History scan ซ้ำ
12. สรุปผลเป็น structured Journal log ที่มี Probe Session ID และ sequence number ชัดเจน

### Out of Scope

- ห้ามแก้ Production `.mqh` หรือ Production EA
- ห้ามแก้ Reducer, Snapshot, Journal schema หรือ WP-06B implementation
- ห้ามสร้าง Position Mapping หรือเปลี่ยน Grid Level state
- ห้ามส่งมากกว่าหนึ่ง Entry Request
- ห้ามส่ง Close Request, Modify Request หรือ Pending Order
- ห้ามใช้ Demo/Live account หรือส่งคำสั่งออกนอก Strategy Tester
- ไม่ทดสอบ Basket/TP/SL หรือ Grid trading behavior
- ไม่พยายามสร้าง Partial Fill ด้วยการส่งหลาย Requests; หลาย Requests ไม่ใช่ Partial Fills ของ Order เดียวกัน
- ไม่สร้างภาระ Transaction จำนวนมากเพื่อทดสอบ queue overflow 1,024 รายการ

## 3. Safety Contract — Hard Gates

Probe ต้องหยุดก่อนส่ง Trade Request หากเงื่อนไขใดไม่ผ่าน:

1. `MQLInfoInteger(MQL_TESTER) == true`
2. `MQLInfoInteger(MQL_OPTIMIZATION) == false`
3. Input `EnableTestTrade == true` (ค่า Default ต้องเป็น false)
4. `ACCOUNT_MARGIN_MODE == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`
5. `TERMINAL_TRADE_ALLOWED`, `MQL_TRADE_ALLOWED`, `ACCOUNT_TRADE_ALLOWED` เป็น true
6. Symbol ปัจจุบันมีข้อมูล Trade/Volume ที่อ่านได้ครบ
7. Test Volume อยู่ในช่วง Min/Max และตรงกับ Volume Step ของ Symbol
8. Probe Magic เป็นค่าบวก และไม่มี Open Position หรือ Active Order ของ Symbol + Magic นี้อยู่ก่อนเริ่ม
9. Probe Session ID ไม่ว่าง ใช้เฉพาะตัวอักษร A-Z/a-z, ตัวเลข, `_` หรือ `-` และไม่มี persisted state ที่อาจทำให้ส่งซ้ำโดยไม่ตั้งใจ
10. ก่อนส่ง Request ต้อง persist สถานะ `REQUEST_STARTED` และ Flush ให้สำเร็จ; หลัง CTrade คืนค่าให้ persist exact Order Ticket เป็น decimal text ทันที
11. หากพบ Session เดิมที่มี `REQUEST_STARTED` แต่ไม่มี durable Order Ticket ให้ Fail Closed และห้ามส่งซ้ำ เพราะอาจเป็นกรณี Server รับคำสั่งแล้วแต่ EA ยังบันทึกผลไม่สำเร็จ
12. ไม่มีการ Retry Trade Request อัตโนมัติ ไม่ว่า retcode ใด

ถ้า `MQL_TESTER` เป็น false ต้อง Fail Initialization โดยเด็ดขาด ห้ามมี fallback ไป Demo/Live

Probe จะส่งเพียง Market Buy หรือ Market Sell หนึ่งครั้งตาม Input โดยไม่กำหนด SL/TP และไม่ส่งคำสั่งปิด Position ที่เกิดขึ้น Position ที่เหลืออยู่เป็นเพียง Position ภายใน Strategy Tester run นั้น

## 4. Event Capture Contract

สำหรับทุก Callback ให้เก็บ:
- Sequence number
- `GetTickCount64()` หรือ monotonic counter ที่ใช้ได้ใน Build
- `TimeCurrent()`
- `trans.type`
- `trans.order`, `trans.deal`, `trans.position`
- `trans.symbol`, `trans.volume`, `trans.price`
- `trans.order_type`, `trans.order_state`, `trans.deal_type`

สำหรับ `TRADE_TRANSACTION_REQUEST` ให้เก็บเฉพาะ field ของ `request` / `result` ที่มีความหมายกับ transaction นี้ เช่น action, symbol, magic, volume, order/deal ticket, retcode, result volume/price

สำหรับ `TRADE_TRANSACTION_DEAL_ADD`:
- บันทึก Deal Ticket จาก `trans.deal`
- ทดลอง `HistoryDealSelect(trans.deal)` หนึ่งครั้งและอ่าน required properties ทันที
- เก็บผล success/failure และ `GetLastError()`
- ห้ามทำ full History scan, file I/O, Reducer mutation หรือ Position Mapping ใน callback

ใช้ bounded buffer ที่มี overflow counter ชัดเจน หาก buffer เต็มต้องบันทึก overflow และห้ามเขียนทับ event เก่าโดยเงียบ ๆ

หมายเหตุ: immediate History probe เป็น diagnostic exception สำหรับ EA ทดสอบเท่านั้น ไม่ใช่ข้อเสนอให้ Production callback อ่าน History หรือทำงานหนัก

## 5. Exact Order → Deal Scan Contract

- ใช้ Order Ticket ที่ได้จาก `CTrade.ResultOrder()` เป็น correlation root
- ต้อง Select exact Order ด้วย `HistoryOrderSelect(order_ticket)` และตรวจ required Order properties
- เก็บ Order setup time ก่อนเรียก `HistorySelect()` เพราะการเปลี่ยน History selection context มีผลต่อรายการที่ถูก Select
- เรียก bounded `HistorySelect()` จาก Order setup time ลบ safety margin ที่กำหนด ไปถึง `TimeCurrent()` บวก margin เล็กน้อย
- Enumerate Deal list ด้วย index และ `HistoryDealGetTicket(index)`; อ่าน properties โดยระบุ Deal Ticket โดยตรง
- อย่าเรียก `HistoryDealSelect()` ระหว่าง enumerate เพราะฟังก์ชันนี้เปลี่ยน selected Deal list ให้เหลือ Deal เดียว
- รับเฉพาะ Deal ที่ `DEAL_ORDER` ตรงกับ Order Ticket แบบ exact เท่านั้น
- อ่าน property ทุกตัวด้วย overload ที่ตรวจสอบ success ได้; property read failure ต้องแสดงเป็น incomplete evidence ไม่ใช่ default value
- บันทึก exact Deal Ticket ทั้งหมด เรียงตามเวลาจริงและ Ticket เพื่อให้ตรวจซ้ำได้
- ตรวจว่า Symbol, Magic, Entry/Deal Type, Position Identifier และ Volume ตรงกับ Request ที่ส่ง
- Aggregate volume ของ exact-order Deals และเปรียบเทียบกับ Requested Volume โดยใช้ tolerance จาก Symbol volume precision/step
- ตรวจจำนวน distinct Position Identifier ที่ได้จาก Deals และเทียบกับ live Position snapshot
- ResultDeal hint ต้องเป็นหนึ่งใน exact-order Deals เมื่อ ResultDeal ไม่เป็นศูนย์; หากไม่พบให้รายงาน discrepancy

## 6. Partial Fill / Position Identity

- ถ้าพบ Deal เดียว: บันทึกเป็น Single Deal; ยังไม่สรุปว่า MT5 ไม่รองรับ Partial Fill
- ถ้าพบหลาย Deals:
  - ตรวจว่าเป็น Order Ticket เดียวกัน
  - ตรวจว่า Position Identifier ทุก Deal เป็นค่าเดียวกัน
  - รวม Volume และตรวจว่าไม่เกิน Requested Volume
  - เก็บราคา/Volume ของทุก Deal เพื่อให้คำนวณ Weighted Average ได้
- ถ้าพบมากกว่าหนึ่ง Position Identifier จาก Order เดียว: รายงานเป็น Critical Contract Conflict และหยุดการตีความต่อ ห้ามรวม Position เองหรือสร้าง Mapping
- ถ้าไม่พบ Deal แต่ Request ถูกยอมรับ: รายงาน unresolved; ห้ามสรุป no-fill จนกว่าการเลือก History และ property access จะสำเร็จและตรวจ exact Order ได้ครบ

## 7. Recovery Simulation และ Restart Limitation

Probe ต้อง persist Order Ticket, Symbol, Magic, Requested Volume, Order setup time (เมื่ออ่านได้), Session ID และ format version เป็น text โดยเก็บ 64-bit identifiers ใน decimal string ห้ามแปลงเป็น double

หลัง exact-order scan รอบแรก:
1. ล้าง volatile callback queue/counters ในหน่วยความจำ
2. อ่าน persisted record กลับ
3. ตรวจ Session ID, format version และ exact Order Ticket
4. หากมีเพียง `REQUEST_STARTED` แต่ไม่มี Order Ticket ให้ Fail Closed และห้าม Retry
5. เรียก exact-order History scan ใหม่จาก persisted state
5. เปรียบเทียบ Deal set / aggregate volume / Position Identifier กับผลรอบแรก

การทดสอบนี้พิสูจน์ได้เพียง **cold-state recovery algorithm ภายใน Tester run เดียว** ไม่ใช่การ Restart EA/Terminal จริง

ข้อจำกัดที่ค้นพบจากเอกสาร MQL5: chart operations หลายรายการไม่มีผลใน Strategy Tester และ `ChartSetSymbolPeriod()` ไม่สามารถใช้บังคับ reinitialization ของ EA ใน Tester ได้ ดังนั้น Probe ห้ามอ้างว่าการล้าง RAM แล้ว reload ใน process เดิมเท่ากับการทดสอบ Terminal Restart จริง

แหล่งอ้างอิงทางการ: [MQL5 Tester limitations](https://www.mql5.com/en/book/automation/tester/tester_limitations) ระบุว่า chart operations เช่น `ChartSetSymbolPeriod()` ไม่มีผลใน Strategy Tester; ดู [ChartSetSymbolPeriod reference](https://www.mql5.com/en/docs/chart_operations/chartsetsymbolperiod) ประกอบ

หากไม่สามารถทำ true restart ภายใน Strategy Tester ได้:
- บันทึก TRUE_RESTART_RECOVERY = NOT_TESTED
- D-06-02 ยังไม่ถือว่าผ่านครบทุกหัวข้อ restart
- เสนอให้แยก restart proof เป็น WP-06E / D-06-06 follow-up โดยไม่ใช้ Demo/Live และรอ Product Owner อนุมัติวิธีทดสอบเพิ่มเติม
- ห้ามใช้การ reinitialize object ใน memory หรือการเรียก recovery function ซ้ำเป็นหลักฐานว่า EA/Terminal restart ผ่าน

## 8. Environment Evidence

ต้องบันทึกในผล Probe:
- Terminal build
- Strategy Tester symbol
- Account margin mode (ต้องเป็น Hedging)
- Symbol execution mode
- Symbol filling mode และ Order filling mode ที่อ่านได้
- Symbol volume min/max/step
- Symbol digits, point, tick size
- Requested side/volume, Magic, Session ID
- Tester tick model / price generation mode จากหน้าต่าง Strategy Tester (ผู้ทดสอบบันทึกเพิ่ม เพราะ EA ไม่ควรเดาค่าจาก runtime)
- Execution delay setting จาก Tester (ผู้ทดสอบบันทึกเพิ่ม)
- วันเวลา/ช่วงข้อมูลทดสอบ และ source revision

## 9. Allowed Files

Implementer แก้ไขได้เฉพาะ:
- `Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5`
- `Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/IMPLEMENTATION_REPORT.md`

ห้ามแก้ไฟล์ Production, shared Include, existing tests หรือ WP-06A/B/C contracts หากพบว่าต้องแก้ให้หยุดและเสนอ Change Request ก่อน

## 10. Official MQL5 References
- [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction) — transaction types, callback behavior, queue capacity and event-ordering caveats.
- [HistoryDealSelect](https://www.mql5.com/en/docs/trading/historydealselect) — selecting one Deal changes the selected Deal list.
- [Selecting orders and deals from history](https://www.mql5.com/en/book/automation/experts/experts_history_select) — History selection context behavior.
- [Strategy Tester limitations](https://www.mql5.com/en/book/automation/tester/tester_limitations) — chart-operation limitations in Tester.
- [ChartSetSymbolPeriod](https://www.mql5.com/en/docs/chart_operations/chartsetsymbolperiod) — chart change/reinitialization semantics outside Tester.

## 11. Acceptance Criteria

- AC-01: Probe ปฏิเสธการทำงานนอก Strategy Tester และใน Optimization
- AC-02: ค่า Default ไม่ส่งคำสั่ง; ส่งได้เมื่อ EnableTestTrade=true เท่านั้น
- AC-03: ส่ง Market Request ได้ไม่เกินหนึ่งครั้งต่อ Session
- AC-04: บันทึก environment และ request result ครบถ้วน
- AC-05: บันทึก Callback type/sequence และ relevant transaction fields ด้วย bounded buffer
- AC-06: บันทึกผล immediate Deal History select/property reads ภายใน callback โดยไม่มี full scan
- AC-07: Exact Order selection และ bounded History scan ทำงานนอก callback
- AC-08: Enumerate Deals ทุกตัวที่ exact `DEAL_ORDER` ตรงกับ Order Ticket; ไม่ใช้ ResultDeal เป็นรายการครบถ้วน
- AC-09: เก็บ Deal properties ที่ WP-06B ต้องใช้ครบ หรือรายงาน incomplete evidence อย่างชัดเจน
- AC-10: ตรวจ Aggregate Volume, distinct Position Identifiers และ live Position evidence ได้
- AC-11: Recovery simulation reload persisted decimal-string Order Ticket แล้วสร้างผล scan ที่เทียบกับรอบแรกได้
- AC-12: รายงาน true EA/Terminal restart เป็น NOT_TESTED หาก Strategy Tester ไม่รองรับการทดสอบจริง
- AC-13: ไม่แตะ Production Reducer/Journal/Position Mapping และไม่มี Close/Modify Request
- AC-14: มี Implementation Report พร้อม Compile evidence แยกจาก Tester evidence
- AC-15: Persist `REQUEST_STARTED` ก่อนส่ง และห้ามส่งซ้ำเมื่อพบ Session เดิมที่ไม่มี durable Order Ticket
- AC-16: หาก persist ผล Order Ticket หลัง Request ไม่สำเร็จ ให้รายงาน ambiguous execution และหยุด; ไม่มี automatic retry
