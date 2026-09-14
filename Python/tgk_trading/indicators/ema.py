from tgk_trading.domain.market_data import CandleSeries

class EMA:

  def __init__(self, period: int):
    self._period = period

  def calculate(self, data: CandleSeries) -> float | None:
    if data.count() < self._period:
      return None

    alpha = 2 / (self._period + 1)

    start_index = self._period - 1

    total = 0.0

    for i in range(self._period):
      candle = data.get(start_index - i)
      total += candle.close

    ema = total / self._period

    for i in range(start_index - 1, -1, -1):
      candle = data.get(i)

      ema = candle.close * alpha + ema * (1 - alpha)

    return ema
