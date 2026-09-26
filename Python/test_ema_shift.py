from datetime import datetime, timedelta

import pandas as pd
import pandas_ta_classic as ta

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.market_data import CandleSeries
from tgk_trading.indicators.ema import EMA

prices = [100, 101, 102, 103, 104, 105]
start_time = datetime(2026, 1, 1)

def create_series(end_index: int) -> CandleSeries:
  series = CandleSeries()

  for i in range(end_index + 1):
    price = prices[i]

    series.append(
      Candle(
        time=start_time + timedelta(minutes=i),
        open=price,
        high=price,
        low=price,
        close=price,
      )
    )

  return series

data = create_series(len(prices) - 1)
ema = EMA(3)

# Test shift is over
value = ema.calculate(data, shift=len(prices))
print(f"EMA Value (Shift={len(prices)}): {value}")

# Test shift is -1
value = ema.calculate(data, shift=-1)
print(f"EMA Value (Shift={-1}): {value}")

for i in range(len(prices)):
  value = ema.calculate(data, shift=i)
  print(f"EMA Value (Shift={i}): {value}")
