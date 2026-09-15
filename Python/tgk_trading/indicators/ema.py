import pandas as pd
import pandas_ta_classic as ta

from tgk_trading.domain.market_data import CandleSeries

class EMA:

  def __init__(self, period: int):
    self._period = period

  def calculate(self, data: CandleSeries) -> float | None:
    if data.count() < self._period:
      return None

    closes = []
    oldest_index = data.count() - 1
    for i in range(oldest_index, -1, -1):
      candle = data.get(i)

      if candle is None:
        raise RuntimeError("Unexpected missing candle")

      closes.append(candle.close)

    ema = ta.ema(pd.Series(closes), length=self._period)

    return ema.iloc[-1]
