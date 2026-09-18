from datetime import datetime

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.market_data import CandleSeries

candle_1 = Candle(
  time=datetime(2026, 9, 12, 10, 0),
  open=2500,
  high=2510,
  low=2495,
  close=2505,
)

candle_2 = Candle(
  time=datetime(2026, 9, 12, 10, 15),
  open=2505,
  high=2515,
  low=2500,
  close=2512,
)

candle_3 = Candle(
  time=datetime(2026, 9, 12, 10, 30),
  open=2512,
  high=2520,
  low=2505,
  close=2515,
)

series = CandleSeries()

series.append(candle_1)
series.append(candle_2)
series.append(candle_3)

print(f"Current: {series.current()}")
print(f"Previous: {series.previous()}")

print(f"get(0): {series.get(0)}")
print(f"get(1): {series.get(1)}")
print(f"get(2): {series.get(2)}")
print(f"get(3): {series.get(3)}")
print(f"Count: {series.count()}")
print(f"New Series Count: {CandleSeries().count()}")
