# Grid Persistence

ไฟล์หลัก: `Include/BotTrade/Grid/GridPersistence.mqh`

## จุดประสงค์

`CTGKGridPersistence` บันทึกและกู้คืนข้อมูลสถานะของ Grid Instance ผ่าน MT5 Terminal Global Variables โดยแยก Namespace ตามบัญชี Symbol และ Instance ID

คลาสนี้ไม่ได้สร้าง Identity ให้ Grid ผู้เรียกต้องส่ง Symbol และ Instance ID ที่ถูกต้องผ่าน `Initialize(symbol, instance_id)`

## Namespace และข้อจำกัด

รูปแบบ Prefix:

```text
TGK.G.<account-login>.<symbol>.<instance-id>
```

ชื่อ Key ต้องไม่เกินข้อจำกัดความยาวของ MT5 Terminal Global Variables โดยโค้ดตรวจว่าชื่อ Key ที่ยาวที่สุดซึ่งใช้ใน Snapshot จะไม่เกิน 63 ตัวอักษร หากยาวเกินจะไม่ยอม Initialize

## ข้อมูล Snapshot

| Suffix | ข้อมูล |
|---|---|
| `schema` | เวอร์ชันโครงสร้างข้อมูล ปัจจุบันคือ 1 |
| `magic` | Magic Number |
| `mode` | โหมด BUY/SELL |
| `state` | Lifecycle State ของ Grid |
| `anchor` | Anchor Price |
| `step` | Grid Step |
| `lot` | Fixed Lot |
| `reset_reason` | เหตุผลที่ต้อง Reset |
| `pending_mode` | โหมดที่รอเปลี่ยน |
| `pending_step` | Grid Step ใหม่ที่รอใช้ |
| `pending_magic` | Magic Number ใหม่ที่รอใช้ |
| `level_count` | จำนวน Level |
| `state_time` | เวลาที่เปลี่ยนสถานะล่าสุด |
| `commit` | Marker ระบุว่า Snapshot บันทึกครบแล้ว |

สถานะราย Level แยกเก็บใน Key รูปแบบ `lv.<index>`

## วิธี Save

1. ตรวจว่า Instance ID และ Symbol ในข้อมูลตรงกับค่าที่ Initialize ไว้
2. ลบ `commit` เก่าและ Flush เพื่อไม่ให้ Snapshot เก่าถูกมองว่าใหม่หลังเขียนข้อมูลไม่ครบ
3. เขียน Schema และฟิลด์ต่าง ๆ ทีละรายการ
4. เขียน `commit` เป็นฟิลด์สุดท้ายเมื่อเขียนข้อมูลทั้งหมดสำเร็จ
5. Flush Global Variables

หาก Save ล้มเหลวระหว่างทาง `Restore()` จะไม่ยอมรับข้อมูลที่ไม่มี Commit Marker

## วิธี Restore

`HasSnapshot()` ใช้ตรวจว่ามี Commit Marker หรือไม่ เพื่อให้ Lifecycle แยกกรณีไม่มี Snapshot ออกจากกรณีมี Snapshot แต่ Restore ไม่สำเร็จได้ โดย `HasSnapshot()` ไม่ได้ยืนยันว่าเนื้อหา Snapshot ถูกต้อง ต้องเรียก `Restore()` เพื่อ Validate อีกครั้ง

Restore ตรวจว่า:

- มี Commit Marker
- มี Schema ที่รองรับ
- ฟิลด์ที่จำเป็นมีอยู่
- ค่า Enum อยู่ในช่วงที่ถูกต้อง
- Level Count ไม่ติดลบ
- สามารถอ่านฟิลด์ทั้งหมดที่จำเป็นได้

สถานะราย Level ต้องเรียก `RestoreLevelState(index, state)` แยกจาก `Restore()`

## การลบข้อมูล

`DeleteState(level_count)` ลบ Snapshot keys และ Level State ตั้งแต่ Level 0 ถึง `level_count - 1` ผู้เรียกจึงต้องส่งจำนวน Level ที่เหมาะสมกับข้อมูลที่ต้องการลบ

## ข้อจำกัดสำคัญ

- Persistence เก็บข้อมูลใน Terminal Global Variables ของ MT5 Terminal ไม่ใช่ไฟล์ฐานข้อมูลภายนอก
- ความถูกต้องของการกู้คืนขึ้นอยู่กับการส่ง Instance ID เดิมให้คลาส
- Persistence ไม่ได้ค้นหา Position ในบัญชี ไม่ได้ส่งคำสั่งซื้อขาย และไม่ได้ตัดสินใจว่าจะเปิด/ปิด Grid
- การเพิ่มหรือลดฟิลด์ที่บันทึกต้องพิจารณา Schema Version และความเข้ากันได้กับข้อมูลเก่า
- การทดสอบที่มีอยู่ตรวจ Save/Restore และข้อมูลราย Level แล้วตามผลที่ผู้ใช้รายงาน แต่ไม่ได้หมายความว่า State Machine ซึ่งจะใช้ข้อมูลนี้พัฒนาเสร็จแล้ว
