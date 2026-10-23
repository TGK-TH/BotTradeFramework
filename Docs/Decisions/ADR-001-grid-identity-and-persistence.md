# ADR-001: แยก Grid Identity ออกจาก Grid Persistence

- สถานะ: ยอมรับ
- วันที่: 2026-10-23

## บริบท

Grid ต้องมีตัวตนที่แยกกันได้เมื่อเปิดหลายกราฟ รวมถึงหลายกราฟที่ใช้ Symbol และ Timeframe เดียวกัน ขณะเดียวกัน Grid ต้องบันทึก Anchor, Grid Step, Mode และสถานะ Level เพื่อกู้คืนการทำงานภายหลัง

หากรวมหน้าที่ทั้งหมดไว้ในคลาสเดียว จะทำให้การสร้าง Identity ผูกติดกับรายละเอียด Snapshot และทำให้ทดสอบแยกส่วนได้ยากขึ้น

## การตัดสินใจ

แยกความรับผิดชอบออกเป็น:

- `CTGKGridIdentity`: ระบุ Instance ID และ Magic Number ของ Grid
- `CTGKGridPersistence`: Save/Restore ข้อมูล Grid โดยใช้ Instance ID ที่ผู้เรียกส่งให้
- `STGKGridInstanceData`: รูปแบบข้อมูลสถานะที่ Persistence จัดเก็บ

## ผลที่ตามมา

- ทดสอบการแยก Identity และการบันทึกข้อมูลได้อย่างอิสระ
- Persistence ไม่ต้องเป็นผู้ตัดสินว่า Grid เป็น Instance ใหม่หรือ Instance เดิม
- โค้ดที่เชื่อมสองส่วนเข้าด้วยกันต้องรับผิดชอบการส่ง Instance ID ที่ถูกต้อง
- การ Restore ข้อมูล Snapshot ไม่ได้พิสูจน์ด้วยตัวมันเองว่า Identity ที่ส่งให้เป็น Identity ของ Grid ที่ควรกลับมาทำงาน

## ข้อจำกัดที่ยังต้องแก้ใน Design ระยะถัดไป

ต้องกำหนด Lifecycle ให้ชัดเจนระหว่างการ Restore กราฟเดิมจาก Profile กับการเปิดกราฟใหม่ด้วยตนเอง โดยเฉพาะเมื่อมี Position ของ Grid ค้างอยู่
