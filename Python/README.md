# TGK BotTradeFramework - Python

Python trading engine สำหรับรัน Strategy และเชื่อมต่อกับ MetaTrader 5 (MT5)

โปรเจกต์นี้ออกแบบให้:

* ใช้ Python บน Mac สำหรับ development, backtest และ test
* ใช้ Python environment ภายใน Wine สำหรับเชื่อมต่อ MT5 และ Live Trading
* ใช้ MT5 เป็น execution layer
* ใช้ `PositionReconciler` เพื่อทำให้ Position ใน MT5 ตรงกับ Target Position ของ Strategy
* รองรับการ restart Bot และ restore Target Position จาก persistent storage

## Requirements

### Development / Test

ต้องมี Python 3.12 และติดตั้ง library:

```bash
pip install pandas
pip install pandas-ta-classic
pip install pytest
```

### MT5 Live Trading

Live Trading ต้องใช้ Python environment ภายใน Wine ซึ่งมี package:

```bash
pip install MetaTrader5
pip install pandas
pip install pandas-ta-classic
pip install pytest
```

โปรเจกต์มี script สำหรับเรียก Python environment ของ Wine:

```bash
./scripts/run_mt5_python.sh
```

ดังนั้นไม่จำเป็นต้องเรียก Python ใน Wine ด้วย path ยาว ๆ ทุกครั้ง

## Project Structure

โครงสร้างหลักของ Python project:

```text
Python/
├── run_mt5_live_engine.py
├── tgk_trading/
│   ├── domain/
│   ├── indicators/
│   ├── strategies/
│   ├── backtest/
│   └── live/
├── test_*.py
└── data/
```

ส่วนสำคัญของ Live Trading:

```text
Strategy
   ↓
LiveEngine
   ↓
PositionReconciler
   ↓
OrderExecutor
   ↓
MetaTrader 5
```

### Strategy

Strategy รับข้อมูล Candle และสร้าง Signal เช่น:

```text
BUY
SELL
NONE
```

### LiveEngine

รับผิดชอบ:

* Warmup Candle
* ตรวจหา Closed Candle ใหม่
* เรียก Strategy
* ส่ง Signal ไปยัง Position Reconciler
* Poll MT5 ต่อเนื่อง

### PositionReconciler

ทำหน้าที่เปรียบเทียบ:

```text
Target Position
      กับ
Actual MT5 Position
```

ตัวอย่าง:

```text
Target = BUY
Actual = ไม่มี Position
→ OPEN BUY
```

หรือ:

```text
Target = SELL
Actual = BUY
→ CLOSE BUY
→ รอรอบถัดไป
→ OPEN SELL
```

### Target Position Persistence

Target Position ถูกเก็บไว้ใน:

```text
Python/data/live_target.json
```

และมี Identity:

```text
symbol
magic
strategy_id
```

เพื่อป้องกัน Target ของ Bot หนึ่งถูกนำไปใช้กับ Bot อื่น

---

# Running Tests

ให้รันจาก Root ของโปรเจกต์:

```bash
PYTHONPATH=Python python3 -m pytest -q
```

ถ้าต้องการดูรายละเอียดมากขึ้น:

```bash
PYTHONPATH=Python python3 -m pytest
```

Test ครอบคลุมส่วนสำคัญ เช่น:

* Domain
* Indicator
* Strategy
* Backtest Engine
* Live Engine
* Position Reconciler
* Target Position Persistence
* Restart Recovery

---

# Running MT5 Live Engine

## 1. Safe Preview

ก่อนส่ง Order จริง ควรทดสอบด้วย Safe Preview:

```bash
./scripts/run_mt5_python.sh Python/run_mt5_live_engine.py --once
```

หรือรันต่อเนื่อง:

```bash
./scripts/run_mt5_python.sh Python/run_mt5_live_engine.py
```

Safe Preview จะไม่ส่ง Order จริงเข้า MT5

Output จะมีเวลาของแต่ละ polling รอบ เช่น:

```text
[2026-10-03 13:00:01] New closed candles: 0
[2026-10-03 13:00:06] New closed candles: 0
[2026-10-03 13:00:11] New closed candles: 0
```

เมื่อมี Closed Candle ใหม่:

```text
[2026-10-03 13:15:01] New closed candles: 1
Latest closed candle: ...
```

## 2. Live Trading

**คำสั่งนี้สามารถส่ง Order จริงเข้า MT5 ได้**

```bash
./scripts/run_mt5_python.sh Python/run_mt5_live_engine.py \
  --live \
  --confirm "LIVE XAUUSD 15 0.01"
```

ก่อนรันต้อง:

1. เปิด MT5
2. Login บัญชีที่ต้องการ
3. ตรวจว่าเป็นบัญชี Demo หากกำลังทดสอบระบบ
4. ตรวจ Symbol
5. ตรวจ Lot Size
6. ตรวจ Magic Number
7. ตรวจว่า Bot อื่นที่กำลังรันอยู่ไม่ใช้ Identity เดียวกัน

Current configuration:

```text
Symbol:       XAUUSD
Magic:        4001
Comment:      TGK_PYTHON
Strategy ID:  CDC_ACCOUNT_3
Order Size:   0.01
```

## MT5 Must Remain Running

Python Live Engine ใช้ MT5 เป็น execution layer ดังนั้นในระหว่าง Live Trading:

```text
Python
  ↓
MetaTrader5 Python API
  ↓
MT5 Terminal
  ↓
Broker
```

ควรเปิด MT5 ไว้ตลอดเวลาที่ Bot ทำงาน

และไม่ควรให้ Mac เข้าสู่ Sleep เพราะ Python process ต้อง polling MT5 อย่างต่อเนื่อง

---

# Position Ownership

Bot จะจัดการเฉพาะ Position ที่เป็นของตัวเอง

Identity หลักคือ:

```text
Symbol
Magic Number
Comment / Strategy Identity
```

ตัวอย่าง:

```text
Symbol = XAUUSD
Magic  = 4001
```

Position ของ Bot อื่นจะไม่ถูกนำมาเป็น Position ของ Python Bot

ดังนั้นสามารถมี Bot หลายตัวทำงานในบัญชี MT5 เดียวกันได้ โดยแต่ละ Bot ต้องใช้ Identity ที่แยกกัน

---

# Restart and Recovery

Live Engine รองรับการหยุดและเปิดใหม่

ตัวอย่าง:

```text
Bot Running
   ↓
Target = BUY
   ↓
Bot ถูกปิด
   ↓
Position ยังอยู่ใน MT5
   ↓
หลายชั่วโมงผ่านไป
   ↓
Bot เปิดใหม่
   ↓
Restore Target = BUY
   ↓
ตรวจ MT5
   ↓
พบ BUY ของตัวเองอยู่แล้ว
   ↓
ไม่เปิดซ้ำ
```

ถ้า Target ยังเป็น SELL แต่พบ BUY อยู่:

```text
Target = SELL
Actual = BUY
   ↓
CLOSE BUY
   ↓
Poll รอบถัดไป
   ↓
OPEN SELL
```

---

# Candle Processing

Live Engine ประมวลผล **Closed Candle** ไม่ใช่ Candle ที่กำลังก่อตัว

ตัวอย่าง M1:

```text
10:37 → Candle ปิด
10:38 → Engine สามารถตรวจพบ Closed Candle 10:37
```

การใช้ Closed Candle ช่วยให้ Strategy ทำงานบนข้อมูลที่ไม่เปลี่ยนแปลงแล้ว

---

# Safety

ค่าเริ่มต้นของ Live Engine คือ:

```text
SAFE PREVIEW
```

ดังนั้นการรัน:

```bash
./scripts/run_mt5_python.sh Python/run_mt5_live_engine.py
```

จะไม่ส่ง Order จริง

การส่ง Order จริงต้องระบุ:

```text
--live
```

และต้องยืนยันด้วย:

```text
--confirm "LIVE XAUUSD 15 0.01"
```

ก่อน Live Trading ทุกครั้งควรตรวจ:

```text
MT5 Account
Symbol
Magic
Lot Size
Strategy
Existing Positions
```

---

# Development Workflow

Workflow ที่แนะนำ:

```text
แก้ Code
   ↓
Run Tests
   ↓
Safe Preview
   ↓
MT5 Demo
   ↓
ตรวจ Order / Position
   ↓
ตรวจ Logs
   ↓
จึงค่อย Live Test
```

สำหรับการพัฒนา Strategy ใหม่ ควรทดสอบผ่าน Backtest Engine ก่อน แล้วจึงนำ Strategy เดียวกันไปใช้กับ Live Engine

แนวคิดสำคัญคือ:

```text
Same Strategy
      ↓
Backtest
      ↓
Live
```

เพื่อให้ Logic ของ Strategy ไม่ถูกเขียนแยกเป็นคนละชุดระหว่าง Backtest และ Live Trading

---

# Current Status

Python Live Trading Engine สามารถ:

* เชื่อมต่อ MT5
* อ่าน Candle
* Detect Closed Candle
* Warmup Historical Candle
* Run Strategy
* Generate Order Request
* Open Position
* Close Position
* แยก Position ด้วย Magic Number
* Reconcile Target กับ Actual Position
* Persist Target Position
* Restore Target หลัง Restart
* Recover เมื่อ Bot ถูกปิดและเปิดใหม่
* Run Safe Preview
* Run Live Trading

ระบบได้รับการทดสอบทั้ง Unit Test และการส่ง Order จริงบน MT5 Demo แล้ว

> การทดสอบ Live ควรเริ่มด้วยขนาด Order เล็ก เช่น `0.01 lot` เพื่อยืนยัน Execution และ Recovery Behavior ก่อนเพิ่มขนาด Position
