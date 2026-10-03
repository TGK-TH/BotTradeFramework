from typing import Protocol

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.market_data import CandleSeries
from tgk_trading.domain.order import Order, OrderSide, OrderType
from tgk_trading.domain.signal import SignalType
from tgk_trading.domain.timeframe import Timeframe
from tgk_trading.live.candle_tracker import ClosedCandleTracker
from tgk_trading.live.order_executor import OrderExecutor
from tgk_trading.live.position_reconciler import PositionReconciler, ReconciliationAction

from tgk_trading.domain.position import PositionSide

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
    order_executor: OrderExecutor,
    order_quantity: float = 1.0,
    position_reconciler: PositionReconciler | None = None
  ):
    self._adapter = adapter
    self._symbol = symbol
    self._timeframe = timeframe
    self._strategy = strategy
    if order_quantity <= 0:
      raise ValueError("order_quantity must be greater than 0")

    self._order_executor = order_executor
    self._order_quantity = order_quantity
    self._tracker = ClosedCandleTracker()
    self._data = CandleSeries()
    self._position_reconciler = position_reconciler or PositionReconciler()

  def warmup(self, count: int = 100) -> list[Candle]:
    candles = self._adapter.get_candles(
      symbol=self._symbol,
      timeframe=self._timeframe,
      count=count
    )

    for candle in candles:
      self._data.append(candle)
      self._strategy.on_candle(self._data)

    self._tracker.mark_processed(candles)
    return candles

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
      self._position_reconciler.set_target(
        signal.type,
        signal_bar_time=candle.time
      )

    self._reconcile_position()

    return new_candles

  def _reconcile_position(self):
    positions = self._order_executor.get_owned_positions()
    action = self._position_reconciler.reconcile(positions)

    if action == ReconciliationAction.CLOSE_AND_OPEN_BUY:
      self._order_executor.close_owned_positions()
      return

    if action == ReconciliationAction.CLOSE_AND_OPEN_SELL:
      self._order_executor.close_owned_positions()
      return

    if action == ReconciliationAction.OPEN_BUY:
      self._order_executor.submit_order(
        Order(
          type=OrderType.MARKET,
          side=OrderSide.BUY,
          quantity=self._order_quantity
        )
      )
      return

    if action == ReconciliationAction.OPEN_SELL:
      self._order_executor.submit_order(
        Order(
          type=OrderType.MARKET,
          side=OrderSide.SELL,
          quantity=self._order_quantity
        )
      )


  def positions(self):
    return self._order_executor.get_owned_positions()

  def last_processed_time(self):
    return self._tracker.last_processed_time()
