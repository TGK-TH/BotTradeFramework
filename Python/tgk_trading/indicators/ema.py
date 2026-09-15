from tgk_trading.domain.market_data import CandleSeries

class EMA:

  def __init__(self, period: int):
    self._period = period

  def calculate(self, data: CandleSeries) -> float | None:
    if data.count() < self._period:
      return None

    alpha = 2 / (self._period + 1)

    oldest_index = data.count() - 1

    total = 0.0

    for i in range(self._period):
      candle = data.get(oldest_index - i)
      total += candle.close

    ema = total / self._period

    for i in range(oldest_index - self._period, -1, -1):
      candle = data.get(i)

      ema = candle.close * alpha + ema * (1 - alpha)

    return ema
