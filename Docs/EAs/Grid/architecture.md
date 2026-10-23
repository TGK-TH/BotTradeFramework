# ภาพรวมสถาปัตยกรรม Grid

อัปเดตล่าสุด: 2026-10-23

## ขอบเขตของเอกสาร

เอกสารนี้อธิบาย Grid components ที่มีอยู่ใน Source Code ณ วันที่อัปเดต ไม่ใช่คำอธิบาย Grid Engine ที่เสร็จสมบูรณ์แล้ว ปัจจุบันมีโครงสร้างข้อมูล ระบบ Identity ระบบ Persistence และ Test framework แต่ยังไม่ได้พัฒนา Grid State Machine/Order Execution ครบตามข้อกำหนด Grid V1

## ส่วนประกอบปัจจุบัน

```text
EA / Test EA
   |
   +--> CTGKGridIdentity
   |       +--> Hidden chart marker
   |       +--> Terminal Global Variables สำหรับ Magic registry/sequence/lock
   |
   +--> STGKGridInstanceData (ประกาศใน GridTypes.mqh)
   |
   +--> CTGKGridPersistence
           +--> Terminal Global Variables สำหรับ Snapshot
           +--> Terminal Global Variables สำหรับสถานะของแต่ละ Level

MQL5 Test EAs
   |
   +--> CTGKTestRunner
           +--> CTGKTestAssert
```

## ไฟล์หลัก

| ไฟล์ | หน้าที่ปัจจุบัน |
|---|---|
| `Include/BotTrade/Grid/GridTypes.mqh` | ประกาศ Enum และโครงสร้างข้อมูลที่ใช้แทนสถานะของ Grid |
| `Include/BotTrade/Grid/GridIdentity.mqh` | สร้าง/กู้คืน Instance ID จากวัตถุที่ซ่อนบนกราฟ และจัดสรร Magic Number |
| `Include/BotTrade/Grid/GridPersistence.mqh` | บันทึกและกู้คืน Snapshot และสถานะราย Level ด้วย Terminal Global Variables |
| `Include/BotTrade/Testing/TestAssert.mqh` | ฟังก์ชัน Assertion พื้นฐาน |
| `Include/BotTrade/Testing/TestRunner.mqh` | จัดกลุ่ม Test นับผล และพิมพ์ PASS/FAIL |

## ขอบเขตที่ยังไม่เสร็จ

- ยังไม่มี Grid State Machine ที่ควบคุม Lifecycle ทั้งหมด
- ยังไม่มีการจัดการคำสั่งซื้อขายหลาย Level ของ Grid ที่สมบูรณ์
- ยังไม่มีการยืนยันจากเอกสารนี้ว่าข้อกำหนดทุกข้อของ Grid V1 ถูกนำไปใช้ในโค้ดแล้ว
- การกู้คืน Identity เมื่อ Restore กราฟจาก Profile ถูกทดสอบแล้วตามผลที่ผู้ใช้รายงาน แต่การเปิดกราฟใหม่ด้วยตนเองถือเป็นสถานการณ์ต่างหาก และต้องกำหนดพฤติกรรมก่อนนำไปใช้กู้คืน Grid ที่มี Position ค้างอยู่

## หลักการแยกความรับผิดชอบ

- Identity ระบุว่า Grid Instance นี้คือ Instance ใด และใช้ Magic Number ใด
- Persistence เก็บข้อมูลสถานะของ Instance ที่ระบุมาให้ แต่ไม่ได้เป็นผู้กำหนด Lifecycle ของ Instance
- Types ประกาศรูปแบบข้อมูลและ Enum โดยไม่ได้ดำเนินการซื้อขายเอง
- Test framework ตรวจเงื่อนไขและรายงานผล ไม่ได้เป็นหลักฐานแทนการทดสอบจริงใน MetaEditor/MT5
