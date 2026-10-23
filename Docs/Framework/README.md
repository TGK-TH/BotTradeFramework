# เอกสาร Framework

พื้นที่นี้ใช้สำหรับเอกสารของสถาปัตยกรรมและ Module ที่ออกแบบให้ EA หลายตัวใช้ร่วมกันได้ โดยไม่ผูกกับ Strategy หรือ State Machine ของ EA ตัวใดตัวหนึ่ง

## ขอบเขตปัจจุบัน

- [MQL5 Test Framework](Testing/mql5-test-framework.md) — `TestAssert` และ `TestRunner` สำหรับเขียนและรายงานผลการทดสอบ

## สิ่งที่ยังไม่ควรสรุปว่าเป็น Shared Module

Grid มีโค้ดเฉพาะตัว เช่น `CTGKGridIdentity`, `CTGKGridPersistence` และ `STGKGridInstanceData` ซึ่งยังมีชื่อและสัญญาการใช้งานผูกกับ Grid อยู่ จึงเก็บเอกสารไว้ใต้ `EAs/Grid/` ก่อน

หาก EA ตัวอื่นต้องการความสามารถคล้ายกัน ให้ตรวจสอบความต้องการและขอบเขตจริงก่อนตัดสินใจย้ายหรือแยกเป็น Shared Module การวางเอกสารในโฟลเดอร์ Framework ไม่ได้ทำให้โค้ดกลายเป็นของใช้ร่วมกันโดยอัตโนมัติ

## หลักการ

- Shared Module ต้องมีหน้าที่และสัญญาการใช้งานที่ชัดเจน
- อย่ารวม Logic เฉพาะ Strategy ไว้ใน Framework เพียงเพื่อให้ดูทั่วไป
- เมื่อมีการยกระดับ Module จาก EA ไปเป็น Shared Module ให้ปรับโค้ด Tests และเอกสารพร้อมกัน
