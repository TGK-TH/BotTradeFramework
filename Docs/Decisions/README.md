# บันทึกการตัดสินใจด้านการออกแบบ (ADR)

ADR (Architecture Decision Record) ใช้บันทึกบริบท ทางเลือก การตัดสินใจ และผลที่ตามมา โดยต้องระบุขอบเขตให้ชัดว่ามีผลกับ Framework ทั้งหมดหรือ EA เฉพาะตัว

## Framework

ยังไม่มี ADR ที่จัดเป็นการตัดสินใจระดับ Framework โดยเฉพาะ

## Grid EA

- [ADR-001: แยก Grid Identity ออกจาก Grid Persistence](../EAs/Grid/Decisions/ADR-001-grid-identity-and-persistence.md)
- [ADR-002: ใช้ Chart ID เป็นจุดตั้งต้น ไม่ใช่เงื่อนไขการ Restore](../EAs/Grid/Decisions/ADR-002-chart-id-is-not-persistence-identity.md)

## รูปแบบ ADR

เอกสารแต่ละฉบับควรมี:
- รหัสและชื่อที่สื่อความหมาย
- Scope: Framework หรือชื่อ EA
- สถานะ: เสนอ / ยอมรับ / แทนที่แล้ว
- วันที่
- บริบทและปัญหา
- ทางเลือกที่พิจารณา (ถ้ามี)
- การตัดสินใจ
- ผลที่ตามมา ข้อจำกัด และงานติดตาม
