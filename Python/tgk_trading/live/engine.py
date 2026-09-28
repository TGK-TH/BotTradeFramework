from tgk_trading.brokers.mt5 import MT5Adapter
from tgk_trading.domain.candle import Candle
from tgk_trading.domain.timeframe import Timeframe
from tgk_trading.live.candle_tracker import ClosedCandleTracker


class LiveEngine:
  def __init__(
    self,
    adapter: MT5Adapter,
    symbol: str,
    timeframe: Timeframe,
    strategy
  ):
    self._adapter = adapter
    self._symbol = symbol
    self._timeframe = timeframe
    self._strategy = strategy
    self._tracker = ClosedCandleTracker()

  def poll(self, count: int = 100) -> list[Candle]:
    candles = self._adapter.get_candles(
      symbol=self._symbol,
      timeframe=self._timeframe,
      count=count
    )

    new_candles = self._tracker.new_candles(candles)

    for candle in new_candles:
      self._strategy.on_candle(candle)

    return new_candles

  def last_processed_time(self):
    return self._tracker.last_processed_time()
