# Grid Entry Execution Resolver / Caller — WP-02

สถานะ: **เสร็จตามผล Compile/Run ที่ผู้ใช้รายงานเมื่อ 2026-11-18**

อัปเดตล่าสุด: 2026-11-18

## 1. เป้าหมายและขอบเขต

WP-02 เชื่อม `STGKGridEntryExecutionCandidate` กับ Level State และ Position Mapping ของ Target Level ที่ Candidate ระบุ เพื่อประกอบ Fresh Context ให้ `CTGKGridEntryExecutionPolicy`. Caller ต้อง Fail Closed เมื่อ provenance, persistent/runtime state หรือ request state ไม่สอดคล้อง และต้องไม่เรียก Policy เมื่อ Resolve ล้มเหลว.

WP-02 ไม่ส่ง Trade Request, ไม่เขียน Persistent Storage และไม่เปลี่ยนกติกา Policy ที่อนุมัติแล้ว. Trade execution และการเชื่อม Entry Pipeline อยู่ใน WP-03/WP-04.

## 2. Dependency Review

- `CTGKGridLevelRuntimeCoordinator` เก็บ Level State ที่ใช้ใน runtime, Anchor State, Symbol, Magic Number และ Mode; เดิมไม่มี Config Epoch match.
- `CTGKGridEntryMappingReducer` เป็น Authority ของ persistent Level State, Position Mapping, Request state และ Recovery Status; เดิมมี target lookup เป็น private implementation.
- `CTGKGridEntryExecutionPolicy` รับ Level Context ที่ Resolve แล้วเท่านั้น; ไม่มี identity/key/provenance fields และไม่สามารถตรวจ Caller ได้ด้วยตนเอง.
- Resolver จึงต้องตรวจ Candidate กับ Reducer identity/config, Coordinator identity/config, target key, state จาก runtime/persistent view, mapping ของ target เดียวกัน และ unresolved request consistency ก่อนเรียก Policy.

## 3. Implementation Contract

### Mapping Reducer read-only queries

- `MatchesContext(instance_id, symbol, magic_number, mode, config_epoch)` คืน `true` เฉพาะ Reducer ที่ initialized, healthy และตรงกับ Instance/Mode/Config ปัจจุบัน.
- `TryGetPositionMapping(is_anchor, level_index, has_position_mapping)` ตรวจ key เป็น Anchor `true/-1` หรือ Normal `false/index>=0`; คืน `false` เมื่อ Reducer unhealthy, key ไม่ถูกต้อง หรือพบ mapping ซ้ำ.
- Output mapping มีความหมายเมื่อ method คืน `true`; Resolve failure ห้ามนำไปตีความเป็น `has_position_mapping=false`.

### Runtime Coordinator context

- `MatchesGridContext(symbol, magic_number, mode, config_epoch)` ตรวจ runtime identity/config ที่ Caller กำลังใช้.
- `BindConfigEpoch(config_epoch)` ผูก Epoch ให้ Coordinator ที่ initialize แล้วได้ครั้งแรก; การเปลี่ยน Epoch ต้องสร้าง Coordinator ใหม่เพื่อไม่ reuse Level State จาก Config เก่า.
- Candidate ของ Normal Level ต้องมี State ที่ตรงกันระหว่าง Coordinator และ Reducer; Anchor ใช้ Anchor State จาก Coordinator และ Mapping จาก Reducer.
- ACTIVE ต้องสอดคล้องกับการมี Position Mapping; ความขัดแย้งเป็น Resolve failure.

### Resolver และ Caller

- `CTGKGridEntryExecutionResolver::Resolve(candidate, coordinator, reducer, level_context)` คืน `false` เมื่อ identity/config/target/state/mapping ตรวจไม่ได้หรือไม่ตรงกัน.
- `CTGKGridEntryExecutionCaller::Evaluate(candidate, coordinator, reducer, execution_state, result)` Resolve Context ใหม่ทุกครั้ง; ตรวจว่า `has_unresolved_request` จาก Coordinator และ Reducer ตรงกัน.
- เมื่อ Resolve ล้มเหลว Caller คืน `false`, ไม่เรียก Policy และไม่เขียนทับ Result; เมื่อ Resolve สำเร็จจึงประกอบ Execution Context และเรียก Policy.
- Resolver ใช้ Persistent Mapping จาก Reducer สำหรับ Target ของ Candidate เท่านั้น; ไม่ใช้ Comment, Fill Price หรือการ scan Position เพื่ออนุมาน Level.

## 4. Test-First Inventory

Test EA: `Experts/TGK/Tests/Grids/test_grid_entry_execution_resolver.mq5`; ใช้ in-memory fixtures และไม่มี Trade Request.

| Group | Test IDs | จำนวน | Coverage |
|---|---|---:|---|
| A — Successful Resolution | A01–A02 | 2 | READY/unmapped Normal Level; mapped Anchor context |
| B — Provenance / Fail Closed | B01–B11 | 11 | Instance ID, Symbol, Magic, Mode, Candidate Epoch, Anchor key, negative/out-of-range Level, unconfigured Reducer, Recovery Error, runtime/persistent State disagreement |
| C — Request / Stale Runtime | C01–C03 | 3 | unresolved state mismatch, coherent unresolved request reaches Policy and blocks, stale Coordinator Config Epoch |
| F — Fresh Context | F01 | 1 | Level 0 unmapped → Level 7 mapped → Level 0 again using the same Caller/Result |
| **Total** |  | **17** |  |

## 5. Acceptance Criteria — WP-02

- Resolver EA มี 17 Test IDs ไม่ซ้ำ; มี direct unit tests สำหรับ Reducer/Coordinator APIs ใหม่ และ fixtures ยืนยันการ Initialize/Replay สำเร็จก่อนใช้ผลทดสอบ.
- `test_grid_entry_mapping_reducer.mq5` ตรวจ `MatchesContext()` exact match, identity/config mismatch, uninitialized และ recovery-error state; ตรวจ `TryGetPositionMapping()` สำหรับ unmapped/mapped Level, mapped Anchor, key invalid, uninitialized และ recovery-error state.
- `test_grid_level_runtime_coordinator.mq5` ตรวจ Mode context, Config Epoch initial binding, same-epoch rebinding, rejected changed epoch, unbound context และ identity/mode/epoch mismatches.
- Caller สร้าง context สำหรับ Candidate's exact Instance/Target/Config Epoch; mapping มาจาก Reducer และ Level State ตรงกับ runtime.
- Failure ใน identity, config, target, recovery, state consistency หรือ request consistency ต้องคืน `false`; Result sentinel ต้องไม่เปลี่ยน แสดงว่า Policy ไม่ถูกเรียก.
- เมื่อ unresolved state สอดคล้องและ Resolve สำเร็จ Policy ต้องคืน `REJECT / UNRESOLVED_REQUEST`.
- F01 ต้องได้ Level 0 `ALLOW / ELIGIBLE`, Level 7 mapped `REJECT / LEVEL_NOT_ELIGIBLE` ตาม precedence ของ Policy, และ Level 0 ซ้ำ `ALLOW / ELIGIBLE`.
- Resolver อ่านข้อมูลสดทุก call; ไม่มี internal cache, persistent mutation, Trade API, CTrade, OrderSend หรือ File I/O.
- Static Review และ `git diff --check` ผ่าน; ไม่มีการกล่าวอ้าง MetaEditor/MT5 Compile/Runtime PASS ก่อนผู้ใช้รายงาน.
- ผู้ใช้ Compile/Run Resolver Test EA, Policy Test EA, Reducer Test EA, Coordinator Test EA และชุด Grid Regression ที่เกี่ยวข้อง; Demo Integration Test ไม่อยู่ใน Gate นี้.

## 6. Files Changed

- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh` — เพิ่ม read-only context/mapping query.
- `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh` — เพิ่ม Mode match, one-time Config Epoch binding และ Epoch-aware context match.
- `Include/BotTrade/Grid/GridEntryExecutionResolver.mqh` — Resolver และ Caller.
- `Experts/TGK/Tests/Grids/test_grid_entry_execution_resolver.mq5` — integration fixtures / 17 tests.
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` — direct unit tests for new read-only context/mapping query APIs.
- `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` — direct unit tests for new context matching and Config Epoch APIs.
- Grid Roadmap, Architecture, Testing, README, Project Status และ Phase Notes.

## 7. ผลตรวจปัจจุบัน

- Static Review: 17 unique Test IDs; delimiter balance, final newline, trailing whitespace และ no-trading dependency checks ผ่าน; `git diff --check` ผ่าน.
- ผู้ใช้รายงานว่า Compile/Run Test ทั้งหมดแล้ว ทุกไฟล์ผ่านหลังแก้ Reducer Test EA.
- Failure เดิม `out-of-range Level query fails | actual=true` เกิดเพราะ assertion ใช้ index 2 ซึ่ง valid; Fixture มี 201 Grid Levels (รวม Anchor) และ valid normal indices 0–199.
- ปรับ out-of-range test index เป็น 200 โดยไม่เปลี่ยน production Reducer; ผู้ใช้ยืนยันผล Compile/Run ผ่านหลังแก้เมื่อ 2026-11-18.
- WP-02 ผ่านตามผลผู้ใช้รายงาน; WP-03 ยังไม่เริ่มจนกว่าจะได้รับอนุมัติแยกจากผู้ใช้.
