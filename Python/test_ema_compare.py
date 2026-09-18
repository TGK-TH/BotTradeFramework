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


df = pd.DataFrame({
  "close": prices
})

library_ema = ta.ema(df["close"], length=3)
manual_ema = EMA(3)


print("Candle | Manual EMA | Library EMA | Difference")
print("-------|------------|-------------|-----------")

for i, price in enumerate(prices):
  series = create_series(i)

  manual_value = manual_ema.calculate(series)
  library_value = library_ema.iloc[i]

  if pd.isna(library_value):
    library_value = None

  if manual_value is None and library_value is None:
    difference = 0.0
  elif manual_value is None or library_value is None:
    difference = None
  else:
    difference = abs(manual_value - library_value)

  print(
    f"{price:>6} | "
    f"{str(manual_value):>10} | "
    f"{str(library_value):>11} | "
    f"{str(difference):>9}"
  )
