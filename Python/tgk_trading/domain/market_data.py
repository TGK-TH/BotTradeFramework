from tgk_trading.domain.candle import Candle

class CandleSeries:

  def __init__(self):
    self._candles = []

  def append(self, candle: Candle):
    self._candles.append(candle)

  def current(self) -> Candle | None:
    if not self._candles:
      return None

    return self._candles[-1]

  def previous(self) -> Candle | None:
    if len(self._candles) < 2:
      return None

    return self._candles[-2]

  # get(0) ---> Get current or latest Candle
  # get(1) ---> Get previous current Candle
  def get(self, index: int) -> Candle | None:
    if index < 0 or index >= len(self._candles):
      return None

    return self._candles[-1 - index]

  def count(self) -> int:
    return len(self._candles)
