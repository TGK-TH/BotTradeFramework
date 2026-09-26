from tgk_trading.domain.candle import Candle


class ClosedCandleTracker:

  def __init__(self):
    self._last_processed_time = None

  def new_candles(self, candles: list[Candle]) -> list[Candle]:
    if not candles:
      return []

    new_candles = [
      candle
      for candle in candles
      if (
        self._last_processed_time is None
        or candle.time > self._last_processed_time
      )
    ]

    if not new_candles:
      return []

    self._last_processed_time = new_candles[-1].time

    return new_candles

  def last_processed_time(self):
    return self._last_processed_time
