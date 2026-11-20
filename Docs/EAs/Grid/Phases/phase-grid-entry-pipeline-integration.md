# Grid Entry Pipeline Integration — WP-04

สถานะ: **กำลังทำ — Contract/Test Plan ถูกกำหนดจาก Roadmap และ Source ปัจจุบัน**
อัปเดตล่าสุด: 2026-11-20

## 1. Baseline ก่อนแก้ไข

- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Branch: `feature/grid-trading`
- HEAD: `9d4a4965a182348dea8a2e01e8b9c23d8dc1998d`
- Working tree: clean จาก `git status --short --untracked-files=all`
- Pre-change Grid Regression: ผู้ใช้รายงานเมื่อ 2026-11-20 ว่ารัน Test ทั้งหมดแล้วผ่านทั้งหมด; เป็น User-reported baseline ไม่ใช่ผลที่ Assistant รันเอง
- ไม่มีการ Compile/Run เพิ่มเติมใน MT5 ก่อนเริ่ม WP-04

## 2. เป้าหมาย

เชื่อม Candidate ที่ Runtime Coordinator เสนอเข้ากับ Entry Resolver/Policy และ Entry CTrade Adapter อย่างเป็นลำดับ พร้อมคงกติกา Persist/Flush Intent ก่อน Trade Request และรอ Deal/Position Reconciliation ก่อนยืนยัน Position Mapping หรือเปลี่ยน Level เป็น `ACTIVE`.

## 3. ขอบเขต

- แปลง Coordinator candidate เป็น `STGKGridEntryExecutionCandidate` โดยใช้ Instance/Symbol/Magic/Mode/Config Epoch และ Target ของ Candidate ปัจจุบันอย่างตรงตัว
- Resolve context สดจาก Runtime Coordinator และ Mapping Reducer; Fail Closed เมื่อ identity, configuration, target, level/mapping state หรือ unresolved request ไม่ตรงกัน
- เรียก Entry Policy; เมื่อไม่ใช่ `ALLOW / ELIGIBLE` ต้องไม่เรียก Adapter/Execution Port
- เมื่อ Policy อนุญาต จึงส่ง candidate และ policy result ให้ Entry Adapter; Adapter เป็นเจ้าของ Intent/Result append และคำสั่ง execute
- ประสาน request outcome กับ Runtime Coordinator ให้หนึ่ง unresolved request ต่อ Instance; ผลที่รับ/รอผลยัง unresolved
- เก็บและส่งต่อ Request ID, Order/Deal ticket และ execution outcome เป็นข้อมูล exact identifier; ห้ามแปลง ticket เป็น `double`
- Unit/Integration Test ใช้ Fake Execution Port เท่านั้นและไม่มี Trade Request จริง
- ไม่เพิ่ม Production EA shell/event handlers, Demo/Strategy Tester trade execution, lifecycle/reset integration หรือ close/transaction reconciliation ทั้งชุด ซึ่งอยู่นอก WP-04 หรือ Work Package แยก
- ไม่สร้าง Position Mapping จาก Comment หรือราคา Fill; WP-04 ไม่ยืนยัน Position Mapping หรือ `ACTIVE` หากยังไม่มีหลักฐาน reconciliation ที่เชื่อถือได้

## 4. Contract และ Safety

1. Candidate ต้องมาจาก Coordinator ที่กำลังทำงาน และ Target key ต้องตรงกันทั้ง Anchor `(true,-1)` หรือ Normal Level `(false,index>=0)`.
2. Resolver ต้องสร้าง fresh context ทุกครั้ง และตรวจ Reducer/Coordinator identity/config/state กับ Target Mapping; ความไม่แน่นอนต้องหยุด flow ก่อน Adapter.
3. Policy ปฏิเสธหรือ Resolve ล้มเหลว: ไม่มี persistent append และไม่มีการเรียก execution port.
4. Policy อนุญาต: Adapter ต้อง persist/apply Intent ก่อนส่ง request; ถ้า Intent/sequence/storage ล้มเหลว ห้ามส่ง request และ fail closed.
5. `DONE`, `DONE_PARTIAL`, `PLACED` ไม่ใช่ Fill confirmation; request คง unresolved จน reconciliation.
6. Order/Deal identifiers เป็น decimal string เท่านั้น; Comment เป็น metadata ไม่ใช่ Mapping Key.
7. ไม่มี Unit Test ส่ง Trade Request จริง; Demo Integration และ Live Trading อยู่นอก scope และห้ามเริ่มโดยอนุมานจาก WP-04 authorization.

## 5. Test Plan ก่อน Implementation

Test EA ใหม่ภายใต้ `Experts/TGK/Tests/Grids/` ใช้ Fake Execution Port และ fixtures ใน memory:

- P01 (implemented): Candidate ที่ถูกต้องผ่าน Resolver/Policy/Adapter; accepted request เก็บ Deal Ticket แบบ decimal string, ยังไม่มี Position Mapping/ACTIVE และ block price check ถัดไปจน reconciliation.
- P02 (implemented): Policy reject ไม่เรียก Adapter, ไม่ append journal และไม่ส่ง request.
- P03 (implemented): Target mismatch หยุดก่อน Policy/Adapter.
- P04 (implemented): Stale Config Epoch หยุดก่อน Policy/Adapter; เพิ่ม coverage สำหรับ Identity/Level state/Mapping mismatch และ Coordinator/Reducer unresolved disagreement.
- P05 (implemented): Intent append/sequence failure ไม่เรียก fake SendMarketOrder และล็อก Coordinator ให้กัน retry.
- P06 (implemented): Terminal `MARKET_CLOSED` ถูกบันทึกและปลด Coordinator/Reducer unresolved state.
- P07 (implemented): Execution result append failure ทำให้ recovery required และไม่เปิด request ซ้ำ.
- P08: Candidate BUY/SELL คงทิศทาง, Symbol, Magic, Target และ Config Epoch ตามต้นทาง; ทดสอบ Anchor และ Normal Level.
- P09: Position/Deal identifier serialization และ mapping state ครอบคลุม partial fill/one Position Identifier.
- P10: Candidate เดียวต่อ price check; candidate ถัดไปถูก defer/ไม่ execute จน reconciliation.
- P11: Malformed/foreign/stale Candidate ไม่แตะ Position นอก Instance/Symbol/Magic.
- P12: Regression ของ Policy/Resolver/Adapter และ Grid suites ที่เกี่ยวข้องหลัง implementation.

## 6. Acceptance Criteria

- Pipeline integration component ใหม่แยก orchestration ออกจาก `CTrade` และทดสอบได้ผ่าน Fake Port.
- ลำดับ Candidate → Resolver → Policy → Adapter → request outcome ชัดเจนและไม่มี bypass Policy/Resolver.
- Fail-closed paths ไม่ส่งคำขอและไม่สร้าง/เปลี่ยน Mapping โดยอาศัยผลที่ไม่ยืนยัน.
- Accepted result ยังคง unresolved; no request duplicate; ไม่มี Level `ACTIVE` ก่อน reconciliation.
- Static Review, `git diff --check`, test inventory, local Markdown links และ Documentation Consistency Gate ผ่าน.
- ผู้ใช้ Compile/Run test EA และ Grid Regression ใน MetaEditor/MT5 แล้วรายงานผลก่อนปิด WP-04.
- ไม่อ้างผล MT5 Compile/Runtime ก่อนผู้ใช้รายงาน; ไม่ Commit/Push.

## 7. ประเด็นเชื่อมกับ WP-05

Roadmap มอบให้ WP-05 เชื่อม partial fill/close, TP/SL/manual close, Deal history และ Position transaction เข้ากับ Mapping/Coordinator/Engine. WP-04 จึงคง execution result และ identifiers ไว้เป็น input ของ reconciliation แต่ไม่ตีความว่า CTrade return/retcode เป็น Position Fill และไม่ทำ Mapping/Level transition เอง. หากตรวจ Source แล้วพบว่าต้องย้ายขอบเขตดังกล่าว จะบันทึก Dependency Review และหยุดถามผู้ใช้ก่อนขยาย Scope.
