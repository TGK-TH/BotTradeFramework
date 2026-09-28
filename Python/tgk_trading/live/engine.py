from typing import Protocol

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.market_data import CandleSeries
from tgk_trading.domain.order import Order, OrderSide, OrderType
from tgk_trading.domain.signal import SignalType
from tgk_trading.domain.timeframe import Timeframe
from tgk_trading.live.candle_tracker import ClosedCandleTracker
from tgk_trading.live.order_executor import OrderExecutor


class CandleProvider(Protocol):
  def get_candles(
    self,
    symbol: str,
    timeframe: Timeframe,
    count: int
  ) -> list[Candle]:
    ...


class LiveEngine:
  def __init__(
    self,
    adapter: CandleProvider,
    symbol: str,
    timeframe: Timeframe,
    strategy,
    order_executor: OrderExecutor
  ):
    self._adapter = adapter
    self._symbol = symbol
    self._timeframe = timeframe
    self._strategy = strategy
    self._order_executor = order_executor
    self._tracker = ClosedCandleTracker()
    self._data = CandleSeries()

  def poll(self, count: int = 100) -> list[Candle]:
    candles = self._adapter.get_candles(
      symbol=self._symbol,
      timeframe=self._timeframe,
      count=count
    )

    new_candles = self._tracker.new_candles(candles)

    for candle in new_candles:
      self._data.append(candle)
      signal = self._strategy.on_candle(self._data)
      order = self._create_order(signal)

      if order is not None:
        self._order_executor.submit_order(order)

    return new_candles

  def _create_order(self, signal):
    if signal.type == SignalType.BUY:
      return Order(
        type=OrderType.MARKET,
        side=OrderSide.BUY,
        quantity=1.0
      )

    if signal.type == SignalType.SELL:
      return Order(
        type=OrderType.MARKET,
        side=OrderSide.SELL,
        quantity=1.0
      )

    return None

  def last_processed_time(self):
    return self._tracker.last_processed_time()
