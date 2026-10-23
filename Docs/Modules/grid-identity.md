# Grid Identity

ไฟล์หลัก: `Include/BotTrade/Grid/GridIdentity.mqh`

## จุดประสงค์

`CTGKGridIdentity` ทำหน้าที่ระบุ Grid Instance ที่ผูกกับกราฟหนึ่งหน้าต่าง และจัดสรร Magic Number ที่ไม่ชนกับ Position/Order ที่มีอยู่ในบัญชีตามการตรวจของคลาสนี้

Identity แยกจาก Grid Persistence: คลาสนี้ดูแลตัวตนของ Instance ส่วนข้อมูลอย่าง Anchor, Grid Step และสถานะ Level อยู่ใน Persistence

## วิธีสร้างและกู้คืน Instance ID

1. `Initialize(chart_id, symbol)` รับ Chart ID และ Symbol ของกราฟ
2. ค้นหาวัตถุกราฟที่ชื่อขึ้นต้นด้วย `TGK_GID_`
3. หากพบ Marker จะอ่าน Instance ID และ Magic Number ที่ฝังอยู่ในชื่อ Marker (ถ้ามี)
4. หากไม่พบ Marker จะสร้าง Marker ใหม่ โดยใช้ Chart ID เป็นส่วนตั้งต้นของ Instance ID เช่น `C<ChartID>`
5. Marker เป็นวัตถุ `OBJ_LABEL` ที่ซ่อน ไม่สามารถเลือกได้ และมีข้อความว่าง

**ข้อควรเข้าใจ:** Chart ID ถูกใช้ตอนสร้าง Identity ครั้งแรก แต่ไม่ใช่กุญแจเดียวสำหรับการกู้คืน หาก Marker ยังอยู่บนกราฟที่ถูก Restore ก็สามารถใช้ Marker เดิมกู้คืน Identity ได้ แม้ไม่ควรสมมติว่า Chart ID ต้องเปลี่ยนหรือคงเดิมในทุกขั้นตอนการจัดการ Profile

## วิธีจัดสรร Magic Number

- Registry key: `TGK.M.<account-login>.<instance-id>`
- Sequence key: `TGK.MSEQ.<account-login>`
- Lock key: `TGK.MLOCK.<account-login>`
- หาก Marker มี Magic Number จะใช้ค่านั้นเป็นหลัก และตรวจว่า Registry ที่มีอยู่ไม่ขัดแย้งกัน
- หาก Registry มี Magic Number อยู่แล้ว จะนำค่าที่บันทึกไว้กลับมาใช้
- หากยังไม่มี จะใช้ Lock และ Sequence เพื่อจัดสรรหมายเลขใหม่ จากนั้นตรวจไม่ให้หมายเลขนั้นตรงกับ Magic Number ของ Position หรือ Order ที่มีอยู่
- เมื่อกำหนด Magic Number แล้ว จะบันทึกลงชื่อ Marker เพื่อช่วยกู้คืนได้ แม้ Terminal Global Variables หมดอายุในช่วงที่ปิดกราฟ

## สิ่งที่ผลทดสอบยืนยันแล้ว

ผู้ใช้รายงานว่า Test EA ต่อไปนี้ Compile และทำงานผ่านใน MetaEditor/MT5:

- `test_grid_identity.mq5`: Initialize ซ้ำบนกราฟเดียวได้ Identity เดิม
- `test_grid_identity_multichart.mq5`: กราฟคนละหน้าต่างได้ Instance ID และ Magic Number ต่างกัน
- `test_grid_restart_persistence.mq5`: การสลับออกจากและกลับเข้า Profile ที่บันทึกไว้ สามารถกู้คืน Identity ได้หลังแก้เงื่อนไข Chart ID

ดูรายละเอียดที่ [คู่มือทดสอบ Grid](../Testing/grid-testing.md)

## ข้อควรระวัง / สิ่งที่ยังไม่สรุป

- การปิดกราฟแล้วเปิดกราฟใหม่ด้วยตนเองอาจสร้าง Marker และ Identity ใหม่ได้ นี่ไม่ใช่การทดสอบแบบเดียวกับการ Restore กราฟเดิมจาก Profile
- หากต้องการให้กราฟใหม่กู้คืน Grid เดิมที่มี Position ค้างอยู่ ต้องออกแบบวิธีค้นหา/ผูกกับ Instance เดิมอย่างชัดเจนก่อน ไม่ควรเลือก Identity จาก Symbol และ Timeframe อย่างเดียว เพราะอาจมีหลาย Grid บนกราฟชนิดเดียวกัน
- การมี Magic Number ไม่ได้ทำให้ Position ถูกจัดการอย่างปลอดภัยโดยอัตโนมัติ; ระบบซื้อขายในอนาคตต้องกรอง Symbol และ Magic Number ให้ถูกต้อง
