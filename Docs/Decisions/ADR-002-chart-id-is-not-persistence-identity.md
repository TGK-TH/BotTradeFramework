# ADR-002: ใช้ Chart ID เป็นจุดตั้งต้น ไม่ใช่เงื่อนไขการ Restore

- สถานะ: ยอมรับ
- วันที่: 2026-10-23

## บริบท

Integration Test ของ Restart Persistence เคยตรวจว่า Chart ID หลัง Restore ต้องไม่เท่ากับ Chart ID ที่บันทึกไว้ แต่ผู้ใช้พบว่าเมื่อสลับ Profile ไปมา การทดสอบกู้คืนข้อมูลสำคัญผ่านทั้งหมด ยกเว้น Assertion นี้

ใน `CTGKGridIdentity` มี Hidden Chart Marker ซึ่งเก็บ Instance ID และ Magic Number จึงไม่ควรใช้การเปลี่ยนแปลงของ Chart ID เป็นหลักฐานตัดสินว่าการ Restore สำเร็จหรือล้มเหลว

## การตัดสินใจ

Chart ID ใช้เป็นส่วนตั้งต้นตอนสร้าง Marker ใหม่เท่านั้น ส่วน Test Restart Persistence ให้พิมพ์ Chart ID เก่า/ใหม่เป็นข้อมูลวินิจฉัย และใช้การกู้คืน Instance ID, Magic Number, Snapshot และ Level State เป็นเงื่อนไขหลัก

## ผลที่ตามมา

- Test ไม่ล้มเหลวเพียงเพราะ MT5 นำ Chart ID เดิมกลับมาใช้
- การทดสอบยังตรวจข้อมูลที่จำเป็นต่อการกู้คืน Grid
- การ Restore Profile และการเปิดกราฟใหม่ด้วยตนเองยังถือเป็นคนละสถานการณ์

## ขอบเขต

การตัดสินใจนี้ไม่ได้หมายความว่า Chart ID ไม่มีประโยชน์ หรือทุกการเปิดกราฟใหม่ต้องกู้คืน Identity เดิม หากต้องการกู้คืน Grid ที่มี Position ค้างอยู่หลังเปิดกราฟใหม่ ต้องมี Design และ Test แยกต่างหาก
