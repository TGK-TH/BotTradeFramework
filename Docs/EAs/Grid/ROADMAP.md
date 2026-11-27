# TGK Grid V1 — Master Roadmap และ Completion Contract

อัปเดตล่าสุด: 2026-11-25

> เอกสารนี้เป็นแผนงานหลักของ Grid V1 สำหรับทั้งผู้พัฒนาและ Codex ใช้ร่วมกับ Source Code, Test EAs และ Phase Notes ที่อ้างอิงไว้ ห้ามถือว่า Roadmap หรือ Design ที่อนุมัติแล้วเป็นหลักฐานว่า Implementation เสร็จ

## 1. เป้าหมาย

Grid V1 คือ Manual Two-sided Grid EA บน MT5 Hedging Account โดยหนึ่ง EA Chart Instance จัดการ Grid ของตนเองอย่างอิสระ รองรับ BUY หรือ SELL ตาม Configuration และต้องไม่ยุ่งกับ Position/Order ของผู้ใช้หรือ EA อื่น

Repository เป็น Technical Source of Truth; `PROJECT_STATUS.md` เป็น Current Status; เอกสารนี้เป็นภาพรวม Roadmap/Completion Contract; เอกสารใน `Phases/` เป็น Design และ Implementation Record ราย Work Package; `Testing/testing.md` เป็น Test Inventory และผลทดสอบที่ผู้ใช้รายงาน

## 2. ข้อกำหนด Grid V1 ที่ตกลงแล้ว

### 2.1 Instance และ Ownership
- ใช้ Symbol จาก Chart (`_Symbol`); ไม่มี User Symbol Input ใน V1
- หนึ่ง Chart Instance เป็น Grid Instance แยกกัน แม้เป็น Symbol/Timeframe เดียวกัน
- Instance ID และ Magic Number ต้องจัดการโดยระบบ ไม่ให้ผู้ใช้กำหนด Magic ซ้ำเอง
- Ownership ต้องตรวจ exact Symbol + Magic Number และเมื่อจำเป็นต้องตรวจ Instance/Account/Server identity เพิ่มเติม
- ห้ามปิด แก้ไข หรือ Adopt Position ของ Manual Trade หรือ EA อื่น
- เปิด Chart ใหม่เอง = Instance ใหม่; การ Restore Chart/Profile เดิมต้องกู้ Identity และ State ของ Instance เดิมตาม Persistence Contract

### 2.2 Configuration และ Initial Entry
- Grid Mode: BUY หรือ SELL
- Upper Bound และ Lower Bound เป็น Hard Filter
- Grid Step ต้องถูกต้องและใช้สร้าง Level จาก Anchor โดยไม่เลื่อน Level เพื่อให้ตรง Bounds
- Fixed Lot เป็นขนาด Entry ตามข้อกำหนด V1
- Initial Entry ทำได้เมื่อราคาอยู่ภายใน Bounds เท่านั้น; ถ้าอยู่นอก Bounds ให้รอ
- Anchor คือราคาที่ Fill จริงของ Initial Position ไม่ใช่ราคาที่ส่ง Request หรือราคาที่คำนวณไว้ล่วงหน้า
- Bounds ที่อยู่นอกตลาดหยุดเฉพาะการเปิด Entry ใหม่; การจัดการ Position เดิมและ TP ต้องทำต่อ

### 2.3 Grid Level และ Entry Logic
- สร้าง Two-sided Levels จาก Anchor ± Grid Step; ใช้ Bounds เป็น Hard Filter และไม่ Shift Level
- Anchor เป็น Special/Re-entry Level แยกจาก Normal Levels
- BUY ใช้ Ask; SELL ใช้ Bid ในการประเมิน Activation/Entry
- BUY: WAIT_ACTIVATION กลับเป็น READY เมื่อราคาเคลื่อนขึ้นผ่าน Level; Entry เมื่อราคาลงแตะ/ผ่าน READY
- SELL ใช้กฎกลับด้าน
- หนึ่ง Price Check เลือก Candidate ได้ไม่เกินหนึ่ง Level; BUY เลือกราคาต่ำที่สุด, SELL เลือกราคาสูงที่สุด
- Level ที่ไม่ได้รับเลือกและถูกข้ามไปอยู่ผิดด้านต้องกลับเป็น WAIT_ACTIVATION; ACTIVE ต้องไม่ถูกเปลี่ยนเพียงเพราะราคาผ่าน
- **WP-05A.2 final behavior (implemented 2026-11-23; review fixes, final user Compile/Test PASS and CTO approval completed 2026-11-24):** `WAIT_RETURN` is consolidated into `READY`; all Full Close reasons use the same current executable-side quote rule to choose `READY` or `WAIT_ACTIVATION`; Partial Close retains `ACTIVE` while Position Volume remains positive.
- Legacy TP/Non-TP close classification was removed by WP-05A.2; the user reported Compile/Test PASS on 2026-11-23. CR-01/CR-02/CR-03 review findings were fixed; Freebuff compiled both Adapter consumers with 0 errors / 0 warnings and the user reported the full no-trade Grid Regression suite PASS on 2026-11-24. CTO Code Review APPROVED 2026-11-24 and WP-05A.2 is Done; see WP-05A.2 CODE_REVIEW.md and IMPLEMENTATION_REPORT.md §§10–11.
- Anchor ใช้กฎ Re-entry เดียวกับ Normal Level แต่ไม่มี Normal Level ซ้ำที่ราคา Anchor

รายละเอียดที่มีผลบังคับใช้ต้องอ่านจาก [Grid Level Engine Design](Phases/phase-grid-level-engine-design.md) และ [Runtime Coordinator Round 1](Phases/phase-grid-level-runtime-coordinator-round-1.md) หากพบข้อความเก่าขัดกัน ให้ใช้ Design/Implementation ที่ใหม่กว่าและบันทึกความขัดแย้งก่อนแก้ Source

### 2.4 Execution, Mapping และ Recovery
- Pure Engine/Policy ไม่ส่ง Trade Request; Execution Adapter เป็นขอบเขตเดียวที่ส่งคำสั่ง
- มี Unresolved Entry Request ได้สูงสุดหนึ่งรายการต่อ Instance; ห้ามส่งซ้ำขณะผลเดิมยังไม่ชัดเจน
- Accepted/PLACED ไม่ใช่หลักฐานว่าเปิด Position แล้ว; ต้องยืนยันจาก Deal/Position Reconciliation ก่อนเปลี่ยน Level เป็น ACTIVE
- Persistent Typed Mapping เป็น Source of Truth สำหรับ Request/Order/Deal/Position/Logical Level; ห้ามใช้ Order Comment หรือราคา Fill โดยประมาณเป็น Mapping Key
- ใช้ Position Identifier เป็น Logical Position Key; Ticket ใช้สำหรับ operation ปัจจุบัน
- Persist + Flush Entry Intent ก่อนส่ง Trade Request; หาก Persist ไม่สำเร็จห้ามส่งคำสั่ง
- ใช้ Snapshot + Journal + dual Manifest protocol ตาม Contract ที่อนุมัติ; ต้องรักษา Recovery State และ Fail Closed เมื่อข้อมูลไม่สามารถยืนยันได้
- Resolver ต้อง Resolve Context ของ Target Level/Instance ที่ Candidate อ้างถึงเท่านั้น; Resolve failure ต้อง Fail Closed และห้ามเรียก Policy ด้วย Mapping=false ที่สมมติขึ้น
- Recovery/Maintenance Error ต้อง Block New Entries แต่ต้องไม่ละทิ้ง Position เดิมหรือหยุด Reconciliation ที่ปลอดภัย

### 2.5 Lifecycle และ Reset
- Mode เปลี่ยน: ปิด Position ของ Grid เดิมทั้งหมดก่อน; รอ Reconciliation ยืนยันว่าเหลือศูนย์ แล้วรอ Initial Entry ของ Mode ใหม่ภายใน Bounds; Fill ใหม่เป็น Anchor ใหม่
- Grid Step เปลี่ยน: ปิด Position เดิมทั้งหมดและรอยืนยันปิดครบ จากนั้นคำนวณ Levels ใหม่โดยใช้ Anchor เดิม
- Close request accepted ไม่เท่ากับปิดสำเร็จ; ต้อง Scan/Reconcile สถานะบัญชีใหม่
- หากไม่มี Position เปิดอยู่ ยังต้อง Restore/รักษา Grid Level State ตาม Persistence Contract ไม่ใช่ลบ Level State ทั้งหมดเพียงเพราะไม่มี Position

## 3. สถานะปัจจุบัน ณ 2026-11-21

### 3.1 Foundations ที่มี Source และผู้ใช้ยืนยันผลทดสอบแล้ว

| Component / Work Package | สถานะหลักฐาน |
|---|---|
| Grid Types, Identity, Magic allocation | Implemented; ผู้ใช้รายงาน Regression ผ่าน |
| Snapshot/Level State Persistence | Implemented; ผู้ใช้รายงาน Regression ผ่าน |
| State Machine + Lifecycle Integration | Implemented; ผู้ใช้รายงาน Compile/Runtime ผ่าน |
| Position Reconciler + Runtime Orchestrator | Implemented; ผู้ใช้รายงาน Compile/Runtime ผ่าน |
| Close Execution Policy/Adapter (Reset close path) | Implemented; ผู้ใช้รายงาน Unit/Regression ผ่าน |
| Close Adapter Demo Integration | ผู้ใช้รายงาน Demo Integration FINAL PASS 2026-11-02 |
| Two-sided Grid Level Engine | Implemented; ผู้ใช้รายงาน Compile/Regression 11/11 PASS 2026-11-04 |
| Grid Level Runtime Coordinator | Implemented; ผู้ใช้รายงาน Test + Regression 12/12 PASS 2026-11-09 |
| Entry Mapping Journal Storage | Implemented; ผู้ใช้รายงาน Compile/Regression ผ่าน 2026-11-12 |
| Typed Mapping Reducer | Implemented; ผู้ใช้รายงาน Compile/Regression ผ่าน 2026-11-15 |
| Snapshot Serialization + Journal Rotation | Implemented; ผู้ใช้รายงาน Snapshot/Reducer/Regression ผ่าน 2026-11-15 |
| Entry Execution Policy — Phase 1 Design | Approved |
| Entry Execution Policy — WP-01 | Implemented; ผู้ใช้รายงาน Policy 44/44 และ Grid Regression 15/15 Compile/Runtime PASS 2026-11-17 |
| WP-05A Persistence Foundation | WP-05A.1/.2 Done; WP-05A.3 DONE 2026-11-25; user-verified PASS and CTO-approved |

ผล Compile/Runtime ในตารางเป็น User-reported เท่านั้น; Codex/Assistant ห้ามเขียนว่าเป็นผลที่ตนเองรัน

### 3.2 Current Work Item

**WP-05 — Persistence / Runtime Restoration / Position Reconciliation:** WP-05A.1/.2/.3 and WP-05B are Done. WP-05B implementation, both CTO remediation rounds, user-reported Compile/Runtime PASS and CTO Formal Code Review APPROVED are complete; Product Owner formally closed the Card and Trello is Done on 2026-11-26. WP-05C is the next dependency; Design/Scope approved, implementation not yet authorized. Dependency order remains WP-05A.3 → WP-05B → WP-05C.

- WP-05A parent: [Trello](https://trello.com/c/4ojeeFID/8-wp-05a-persistence-foundation); parent tracking remains separate from completion of its child work packages.
- WP-05A breakdown: [WP-05A README](WorkPackages/WP-05A/README.md).
- WP-05A.1 Anchor State Model: Done; user Compile/Test PASS and CTO APPROVED 2026-11-21.
- WP-05A.2 Anchor State Transitions: Done / formally closed 2026-11-24; CR-01/CR-02/CR-03 resolved; user-reported full no-trade Grid Regression PASS; CTO APPROVED. See `WorkPackages/WP-05A/Phase-1.2/`.
- WP-05A.3 Anchor State Persistence Integration & Hardening: [Trello](https://trello.com/c/gaSElnBj/14-wp-05a3-anchor-state-persistence-integration-hardening); DONE 2026-11-25; Product Owner-reported Compile/Runtime PASS; CTO Code Review APPROVED; Trello Card moved to Done.
- WP-05B Runtime State Restoration: [Trello](https://trello.com/c/86s3rVfy/9-wp-05b-runtime-state-restoration); **DONE 2026-11-26**. Restores canonical Snapshot/Journal state into Engine/Coordinator; does not scan/reconcile live account positions. User-reported Compile/Runtime PASS; CTO Formal Code Review APPROVED. See `WorkPackages/WP-05B/CODE_REVIEW.md` and `IMPLEMENTATION_REPORT.md`.
- WP-05C Open Positions Reconciliation: [Trello](https://trello.com/c/c6iAiBw6/10-wp-05c-open-positions-reconciliation); Design/Scope approved by Product Owner 2026-11-25; SPEC/TEST_PLAN finalized: `WorkPackages/WP-05C/`. Uses complete/stable Open Positions snapshots to reconcile by Position Identifier. Full Close is reason-free; Closing Deal History and TP/NON_TP classification are out of scope. Existing Entry Deal Association remains separate and unchanged. Implementation NOT AUTHORIZED.
- WP-05D Production Event Integration remains a separate roadmap placeholder and is not authorized.
- WP-05A.3 and WP-05B have completed implementation, user verification and CTO review; both are formally closed. WP-05C Design/Scope is approved and remains the next implementation dependency; it requires its own fresh pre-change no-trade baseline and explicit PO authorization.
- Workflow: multiple related Cards may be designed/planned in parallel; the user selects the Implementer (current preference: Codex until monthly quota is exhausted, then Freebuff). Implementation, User Verification, and CTO formal Code Review remain sequential, one Card at a time. ChatGPT prepares neutral handoffs and does not select/switch agents.

### 3.3 จำนวน Test Sources ปัจจุบัน

มีไฟล์ `.mq5` ใน `Experts/TGK/Tests/Grids/` จำนวน 21 ไฟล์ ณ วันที่อัปเดต:
- 15 existing component/regression test files ที่เป็น baseline ก่อน Policy Test
- `test_grid_entry_execution_policy.mq5` เป็น Policy Test EA; ผู้ใช้รายงาน Compile/Run ผ่าน
- `test_grid_entry_execution_resolver.mq5` เป็น Resolver/Caller Integration Test EA; ผู้ใช้รายงาน Compile/Run ผ่านเมื่อ 2026-11-18
- `test_grid_entry_execution.mq5` เป็น WP-03 Entry Adapter Unit Test EA จำนวน 13 cases; ผู้ใช้รายงาน Compile/Run ผ่านเมื่อ 2026-11-19
- `test_grid_entry_execution_pipeline.mq5` เป็น WP-04 Fake Port Pipeline Test EA จำนวน 9 Test IDs (P01–P08, P11); ผู้ใช้รายงาน Compile/Run Tests ทั้งหมดผ่านเมื่อ 2026-11-20
- `test_grid_runtime_restoration.mq5` เป็น WP-05B no-trade Runtime Hydration Test EA ครอบคลุม B-01 ถึง B-13; ผู้ใช้รายงาน Compile/Run PASS บน Source ล่าสุดเมื่อ 2026-11-26
- `test_grid_order_execution_demo.mq5` เป็น Demo Integration Test แยกจาก Unit/Regression suite และมี Trade Request จริงบน Demo ตาม Safety Gate

ให้ตรวจไฟล์ใน Directory จริงก่อนนับหรือกำหนด Regression Suite ใหม่; อย่า Hard-code จำนวน 12/13 จากเอกสารเก่าโดยไม่ตรวจรายการล่าสุด

## 4. Roadmap งานที่เหลือจนถึง Grid V1

รายการด้านล่างเป็น Work Packages ตาม Dependency ไม่ได้บังคับว่าต้องคงเป็นเลข Phase เดียวตลอด Codex สามารถแบ่งเป็น Phase ย่อยที่ทดสอบได้ แต่ต้องรักษาลำดับ Dependency และบันทึกสถานะในเอกสาร

| ลำดับ | Work Package | สถานะ | ผลลัพธ์ที่ต้องส่งมอบ |
|---|---|---|---|
| WP-01 | Entry Execution Policy Implementation | COMPLETE (USER-REPORTED PASS) | Header ตาม Phase 2 Contract; Policy Test EA 44 cases และ Full Regression ผ่านตามผู้ใช้รายงาน; ไม่มี Trade API/Mutation |
| WP-02 | Target-Level Resolver / Caller Integration | COMPLETE (USER-REPORTED PASS 2026-11-18) | Resolve Candidate ไปยัง Level/Instance/Config Epoch ที่ถูกต้อง; Fresh Context; Resolver failure Fail Closed; Integration tests พิสูจน์ provenance และ Level 0/7 mapping scenario |
| WP-03 | Entry CTrade Adapter | COMPLETE (USER-REPORTED PASS 2026-11-19) | Persist/Flush Intent ก่อนส่ง Market Entry; retcode/result handling; ไม่ถือ Accepted เป็น Fill; ไม่มี duplicate request; seam/unit tests ไม่ส่ง Trade Request |
| WP-04 | Entry Pipeline Integration | COMPLETE (user-reported Compile/Run PASS 2026-11-20) | เชื่อม Coordinator Candidate → Resolver → Policy → Entry Adapter → Coordinator request state; accepted/uncertain request รอ Deal/Position reconciliation; ห้ามสร้าง Mapping หรือ ACTIVE จาก CTrade result |
| WP-05 | Persistence / Runtime Restoration / Position Reconciliation Integration | IN PROGRESS (WP-05A.1/.2/.3 and WP-05B Done; WP-05C not yet authorized) | WP-05A.3 Anchor Snapshot/Rotation hardening → WP-05B canonical runtime restoration → WP-05C complete/stable Open Positions reconciliation; WP-05D Production Event Integration remains a separate placeholder. Full Close is reason-free; no Closing Deal History or TP/NON_TP classification. |
| WP-06 | Production EA Lifecycle/Event Handler | NOT STARTED | EA shell และ OnInit/OnDeinit/OnTick/OnTimer/OnTradeTransaction ตามที่จำเป็น; initialize identity/config/storage/runtime อย่างถูกลำดับ; restart/recovery และ safe shutdown |
| WP-07 | Configuration, Bounds และ Runtime Safety Integration | NOT STARTED | Inputs และ validation ของ Mode/Bounds/Step/FixedLot; initial entry เฉพาะใน Bounds; no new entries นอก Bounds แต่ manage existing positions ต่อ; reset Mode/Step ตาม Contract |
| WP-08 | End-to-End Test & Demo Validation | NOT STARTED | Integration Test ครอบคลุม BUY/SELL, multi-level crossing, TP/re-entry, partial fills/closes, foreign-position isolation, restart, Mode/Step reset, Storage failure และ Recovery; Demo Test เฉพาะเมื่อผู้ใช้อนุมัติขั้นตอน Trade Request |
| WP-09 | Grid V1 Acceptance & Documentation Freeze | NOT STARTED | รัน full regression; compile production EA; user-run MT5 Strategy Tester/Demo validation ตาม agreed matrix; ตรวจ acceptance checklist ทุกข้อ; docs/status/Trello ปิดครบ |

**ข้อควรระวังเรื่องลำดับ:** WP-05, WP-06 และ WP-07 อาจมี Dependency ย้อนกลับกันเมื่ออ่าน Source จริง; ก่อนเริ่มแต่ละ Work Package ให้ทำ Dependency Review และปรับลำดับใน Roadmap พร้อมเหตุผล ห้ามฝืนลำดับตารางหาก Source/Tests แสดง Dependency ที่ต่างออกไป

## 5. Definition of Done — Grid V1

Grid V1 จะถือว่าเสร็จได้เมื่อครบทุกข้อ ไม่ใช่เมื่อ Components แยกชิ้นผ่าน Unit Tests เท่านั้น

### Functional
- [ ] Initial BUY/SELL Entry ทำงานตาม Mode และเปิดได้เฉพาะภายใน Bounds
- [ ] Anchor ใช้ราคาที่ Fill จริง
- [ ] สร้าง/จัดการ Two-sided Levels ตาม Anchor + Step และ Hard Bounds
- [ ] Bid/Ask touch/cross, activation, candidate selection และ one-candidate-per-check ถูกต้อง
- [ ] TP close แล้วรอ Return ที่ Level เดิม; Non-TP/partial close ทำงานตาม Contract
- [ ] Entry/TP/close/re-entry ทำงานได้หลาย Level โดยไม่ทำให้ Level อื่นเปลี่ยน State ผิด
- [ ] Bounds นอกตลาดหยุดเฉพาะ New Entry; Existing Position management ทำต่อ
- [ ] Mode/Step reset ทำงานตามลำดับ Close → Reconcile → Rebuild/Wait Initial Fill

### Execution / Safety
- [ ] ทุก Position/Order ถูกกรองด้วย Symbol + Instance Magic; Foreign/Manual positions ไม่ถูกแตะ
- [ ] Entry Intent Persist + Flush ก่อน Trade Request
- [ ] ไม่มี duplicate Entry ขณะ Unresolved Request
- [ ] Accepted/Placed ไม่ทำให้ Level ACTIVE จนกว่าจะ Reconcile Position จริง
- [ ] Mapping ไม่พึ่ง Order Comment หรือ approximate Fill Price
- [ ] Storage/Resolver/Identity/Execution failure ใช้ Fail Closed; Existing Positions ยังถูก Reconcile/จัดการต่อได้อย่างปลอดภัย
- [ ] ไม่มีการส่งคำสั่งจริงใน Unit Tests; Demo Trade Tests ต้องมี Safety Gate และการอนุมัติแยก

### Persistence / Lifecycle
- [ ] Restart/Chart Profile restore กู้ Instance Identity, Config, Anchor, Level States, Mapping และ Pending Request ได้
- [ ] ไม่มี Position เปิดอยู่แต่ Level State ที่ยังจำเป็นถูกลบทิ้ง
- [ ] Chart ใหม่สร้าง Instance ใหม่และไม่ Adopt Position ของ Instance เดิม
- [ ] Mode/Step reset ที่ค้างระหว่าง Restart กลับมาทำต่อได้อย่างปลอดภัย

### Validation / Documentation
- [ ] Test Plan ครอบคลุม Unit, Integration, Failure/Recovery และ End-to-End scenarios
- [ ] ทุก Test EA ที่อยู่ใน Full Regression Suite Compile/Run ผ่านใน MetaEditor/MT5 ตามที่ผู้ใช้รายงาน
- [ ] Production EA Compile ผ่านและทดสอบใน MT5 ตาม Matrix ที่ผู้ใช้อนุมัติ
- [ ] Static review, diff check, local Markdown links และ documentation consistency ผ่าน
- [ ] `PROJECT_STATUS.md`, Grid README, Architecture, Testing, Phase Notes และ Serena current-phase memory สอดคล้องกับ Source/Test ล่าสุด
- [ ] ผู้ใช้ยืนยัน Grid V1 Acceptance ก่อนทำเครื่องหมาย Done

## 6. กติกาการทำงานของ Codex

1. เริ่มทุก Task ด้วยการอ่าน `AGENTS.md`, `PROJECT_STATUS.md`, เอกสารนี้, `Docs/EAs/Grid/README.md`, `architecture.md`, `Testing/testing.md` และ Phase Note ที่ตรงกับ Work Package ปัจจุบัน
2. ตรวจ `git status --short` ก่อนแก้ไฟล์ทุกครั้ง; รักษา staged/unstaged changes ของผู้ใช้ ห้าม reset/checkout/clean/stash หรือเขียนทับงานที่ไม่เกี่ยวข้อง
3. ตรวจ Source จริงและ Test Inventory ก่อนสรุปสถานะ; เอกสารอาจเก่า ห้ามเชื่อจำนวนไฟล์/ชื่อ API ที่ไม่ได้ตรวจ
4. ก่อนเริ่ม Source feature/refactor ให้ผู้ใช้รัน latest Grid Regression Tests และบันทึกผล Pre-change; หลังแก้ต้องรัน Regression ซ้ำ
5. Test-first: เขียน/ทบทวน Acceptance Criteria และ Tests ก่อน implementation; ใช้ Test EAs ใน `Experts/TGK/Tests/Grids/`
6. ทำงานทีละ Work Package; ไม่ข้าม Dependency และไม่ขยาย Scope โดยไม่บันทึกเหตุผล
7. เมื่อ Work Package/Phase ปัจจุบันเสร็จ ให้หยุดและขออนุมัติจากผู้ใช้ก่อนเริ่ม Phase ถัดไปทุกครั้ง แม้ Kickoff Prompt ก่อนหน้าจะอนุมัติให้ทำ Grid V1 ตาม Roadmap จนเสร็จก็ตาม
8. เมื่อผู้ใช้ออนุมัติ Phase ใหม่ ให้ตรวจ Trello Card ที่ตรงกับ Scope; ถ้าไม่มี Card แยกที่เหมาะสม ให้สร้างก่อนเริ่มงาน และอัปเดต Card ตามสถานะจริงตลอดงาน
9. Blanket Authorization ไม่ครอบคลุม Live Trading, Demo Test ที่ส่ง Trade Request, การลบ/ปิด Position ที่ไม่ใช่ Test Position, การเปลี่ยน Product Scope หรือการตัดสินใจ Design ที่มีหลายทางเลือกและยังไม่เคยตกลง; กรณีเหล่านี้ต้องหยุดถามผู้ใช้
10. เมื่อถึง MetaEditor/MT5 Gate ให้ส่งรายการไฟล์/ขั้นตอนทดสอบและหยุดรอผลผู้ใช้; ห้ามอ้าง Compile/Runtime PASS จาก Static Checks หรือการอ่าน Source
11. เมื่อผลผู้ใช้ PASS ให้แก้/ปิด Gate ปัจจุบันตามหลักฐาน แล้วหยุดที่ขอบเขต Phase และขออนุมัติผู้ใช้ก่อนเริ่ม Phase ถัดไป; ถ้า FAIL ให้แก้เฉพาะสาเหตุและรัน Regression ซ้ำ
12. หลังแต่ละ Work Package ให้ Update `PROJECT_STATUS.md`, Docs ที่เกี่ยวข้อง, Testing Inventory, Trello Card และ Serena current-phase memory; บันทึก changed files, checks, user-reported outcomes, known gaps และ exact next step
13. ไม่ Commit/Push เว้นแต่ผู้ใช้สั่ง; ไม่แก้ MT5-linked copy นอก Repository
14. ก่อนประกาศ Grid V1 Complete ให้ตรวจ Definition of Done ทุกข้อและขอ User Acceptance

## 7. เอกสารที่เป็น Authority

- [Project Status](../../../PROJECT_STATUS.md) — Current state และ exact next step
- [Grid README](README.md) — Grid documentation index
- [Architecture](architecture.md) — Source architecture และ implementation boundaries
- [Testing Guide](Testing/testing.md) — Test inventory และผลทดสอบ
- [Grid Entry Execution Policy](Phases/phase-grid-entry-execution-policy.md) — Current approved contract/Test-First specification
- [Grid Entry Execution Adapter Round 1](Phases/phase-grid-entry-execution-adapter-round-1.md) — Persistent Mapping/Reducer/Snapshot contract
- [Grid Level Engine Design](Phases/phase-grid-level-engine-design.md) — Level behavior
- [Grid Level Runtime Coordinator Round 1](Phases/phase-grid-level-runtime-coordinator-round-1.md) — Candidate/Request/Mapping coordination
- [Development Workflow](../../Development/workflow.md) — Repository-wide workflow

หากเอกสารขัดแย้งกัน ให้หยุดระบุความขัดแย้งก่อนแก้ Source; ใช้ผล User-approved decision ที่ใหม่กว่าเป็นหลัก และอัปเดตเอกสารที่เก่ากว่าให้สอดคล้อง


## 7. Strategy Tester First — Roadmap Addendum (2026-11-27)

Product Owner has explicitly reprioritized Grid V1: make the current Grid operational on MT5 Strategy Tester first, collect reproducible trading data, then complete Multi-Position Architecture before broker Demo.

### 7.1 Current Milestone — WP-06 Production EA / Strategy Tester Integration

CTO Design & Planning is active; implementation is NOT authorized. The detailed decomposition and design drafts are in [WP-06 README](WorkPackages/WP-06/README.md), [Architecture](WorkPackages/WP-06/ARCHITECTURE.md), and [Open Decisions](WorkPackages/WP-06/WP-06_DECISIONS.md).

| WP | Work Package | Current Planning State | Outcome |
|---|---|---|---|
| WP-06A | Production EA Bootstrap & Recovery Gate | Design Draft | Production EA shell, configuration validation, Identity, canonical restore and WP-05C gate release |
| WP-06B | Trade Event Intake & Entry Deal Correlation | Design Draft | Exact durable Request/Order/Deal association required before Position reconciliation |
| WP-06C | Initial Anchor & Grid Entry Runtime | Design Draft | Initial fill becomes Anchor; normal Grid Candidate → Resolver → Policy → Adapter → Reconciliation flow |
| WP-06D | Position Management, TP & Configuration Reset | Design Draft; TP decision pending PO | Existing-position management, approved TP behavior, Mode/Step reset |
| WP-06E | Strategy Tester End-to-End Readiness | Design Draft | Production EA compile and agreed Hedging Strategy Tester functional matrix |

### 7.2 Strategy Tester / Demo Separation

1. Strategy Tester Readiness (WP-06A through WP-06E).
2. Strategy Tester Validation and reproducible trade-data collection.
3. Multi-Position Architecture for one Entry Request / Grid Level to multiple Position Identifiers.
4. Demo Readiness & Demo Validation.

The current one Entry Request : one Position Identifier contract is only acceptable for a specifically verified Tester configuration. Do not assume the Tester always guarantees this. Conflicting or ambiguous evidence must fail closed and trigger architecture review.

WP-05D full Production Event Integration is deferred for Demo readiness. WP-06B may implement only the minimum event/deal evidence bridge proven necessary for Strategy Tester. CR-07 remains deferred until the Multi-Position contract is approved and its criteria are rewritten.

### 7.3 Open Product / Architecture Decisions

- The per-Position broker-side TP rule is already approved: BUY actual fill + one GridStep; SELL actual fill − one GridStep; no Basket TP. CTO must verify that reason-free Full Close + Level/quote state preserves the required retouch-before-reentry behavior.
- CTO must verify MT5 Strategy Tester trade-event ordering and decide between OnTradeTransaction with bounded History fallback versus serialized History polling.
- Initial Anchor + Position Mapping must be durably bootstrapped atomically from actual fill evidence.
- Lifecycle and canonical Reducer configuration authority must be unified/validated before implementation.
- Restart/recovery validation must distinguish true EA/terminal restart from in-memory reinitialization.

No Demo/Live execution, no implementation, and no commit/push are authorized by this roadmap addendum.
