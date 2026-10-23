# Phase: Grid Integration Testing

- สถานะ: เสร็จสมบูรณ์ตามผลทดสอบที่ผู้ใช้รายงาน
- วันที่ปิด Phase: 2026-10-23

## เป้าหมาย

เพิ่มการทดสอบที่ครอบคลุมการทำงานร่วมกับ MT5 Terminal และ Chart API มากกว่าการทดสอบชนิดข้อมูลและเมธอดแยกส่วน โดยไม่ส่งคำสั่งซื้อขาย

## งานที่ทำ

- เพิ่ม Test EA สำหรับตรวจ Identity บนหลายกราฟ
- เพิ่ม Test EA แบบสองรอบเพื่อตรวจการ Restore Identity และ Persistence หลัง Restore กราฟ/โปรไฟล์
- ปรับ Restart Test ไม่ให้บังคับว่า Chart ID ต้องเปลี่ยน เพราะ Chart ID ไม่ใช่ Identity ถาวรของ Grid

## ไฟล์ที่เกี่ยวข้อง

- `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5`
- `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5`
- `Include/BotTrade/Grid/GridIdentity.mqh`
- `Include/BotTrade/Grid/GridPersistence.mqh`

## ผลทดสอบ

ผู้ใช้ยืนยันว่า:

- Multi-chart Identity Test Compile และ Run ผ่าน
- Restart Persistence Test ผ่านหลังเปลี่ยน Chart ID จาก Assertion เป็น Diagnostic Log
- การสลับไป Profile อื่นและกลับ Profile เดิมสามารถ Restore Identity และข้อมูล Persistence ตามเงื่อนไขที่ทดสอบได้

## สิ่งที่ Phase นี้ไม่ได้พิสูจน์

- ไม่ได้พิสูจน์ว่าการปิดกราฟแล้วเปิดกราฟใหม่ด้วยตนเองจะกู้คืน Grid Instance เดิม
- ไม่ได้พิสูจน์ว่า Grid State Machine หรือ Order Execution ทำงานครบถ้วน เพราะยังไม่ได้พัฒนาใน Phase นี้
- ไม่ได้ทดสอบการกู้คืน Grid ที่มี Position จริงค้างอยู่หลังการปิดกราฟ

## ขั้นตอนถัดไป

ก่อนพัฒนา Grid State Machine ต้องตกลง Lifecycle ของ New Grid Instance และ Restore Existing Grid Instance ให้ชัดเจน รวมถึงวิธีจัดการ Position ที่ยังเปิดอยู่ และรัน Regression Tests ที่เกี่ยวข้องตาม Workflow
