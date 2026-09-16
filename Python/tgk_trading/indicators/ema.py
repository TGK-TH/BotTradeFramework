import pandas as pd
import pandas_ta_classic as ta

from tgk_trading.domain.market_data import CandleSeries

class EMA:

  def __init__(self, period: int):
    self._period = period

  def calculate(self, data: CandleSeries, shift: int = 0) -> float | None:
    dataSize: int = data.count()
    if dataSize < self._period \
      or shift >= dataSize \
      or shift < 0:
      return None

    closes = []
    oldest_index = dataSize - 1
    for i in range(oldest_index, -1, -1):
      candle = data.get(i)

      if candle is None:
        raise RuntimeError("Unexpected missing candle")

      closes.append(candle.close)

    ema = ta.ema(pd.Series(closes), length=self._period)
    value = ema.iloc[-1 - shift]

    return None if pd.isna(value) else value
