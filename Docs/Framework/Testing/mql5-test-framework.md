# ระบบทดสอบ MQL5

ไฟล์หลัก:

- `Include/BotTrade/Testing/TestAssert.mqh`
- `Include/BotTrade/Testing/TestRunner.mqh`

## CTGKTestAssert

ให้ Assertion พื้นฐาน:

- `True(actual)`
- `False(actual)`
- `EqualInt(actual, expected)`
- `EqualLong(actual, expected)`
- `EqualDouble(actual, expected, tolerance)`
- `EqualString(actual, expected)`

แต่ละเมธอดคืนค่า Boolean ว่าเงื่อนไขผ่านหรือไม่ ตัวคลาสนี้ไม่เก็บยอดรวมผลทดสอบ

## CTGKTestRunner

ทำหน้าที่จัดกลุ่ม Test และรายงานผลผ่าน Experts Log:

1. เริ่ม Suite ด้วย `BeginSuite(name)`
2. เริ่ม Test ด้วย `BeginTest(name)`
3. เรียก Assertion อย่างน้อยหนึ่งรายการ
4. ปิด Test ด้วย `EndTest()`
5. ปิด Suite ด้วย `EndSuite()`

Runner นับจำนวน Test และ Assertion ที่ผ่าน/ไม่ผ่าน พร้อมพิมพ์ `FINAL RESULT: PASS` หรือ `FINAL RESULT: FAIL`

**กติกาสำคัญ:** Test ที่ไม่มี Assertion จะถูกนับว่าไม่ผ่าน เพื่อป้องกัน Test ว่างที่รายงานว่าผ่านโดยไม่ตรวจอะไรเลย

หากเรียก `BeginTest()` ขณะที่ Test ก่อนหน้ายังไม่ถูกปิด Runner จะปิด Test ก่อนหน้าให้โดยอัตโนมัติ

## การใช้งานโดยทั่วไป

Test EA แต่ละตัวอยู่ภายใต้ `Experts/TGK/Tests/` แยกตามโดเมน เช่น `Framework/` และ `Grids/` การแยกโฟลเดอร์ช่วยให้เพิ่ม Test สำหรับ Module อื่นในอนาคตได้โดยไม่รวมทุกอย่างไว้ที่เดียว

## ข้อจำกัด

- Runner ทำงานแบบ synchronous
- ไม่ได้ส่ง Order และไม่พึ่งพาข้อมูลตลาดโดยตัวมันเอง
- Test EA บางตัวอาจเรียก API ของ MT5 เช่น Chart API หรือ Terminal Global Variables เพื่อทดสอบ Integration
- การตรวจโค้ดหรือ `git diff --check` ไม่ใช่สิ่งทดแทนการ Compile/Run ใน MetaEditor/MT5
