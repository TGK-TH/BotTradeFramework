from datetime import datetime

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.order import OrderSide, OrderType
from tgk_trading.domain.signal import Signal, SignalType
from tgk_trading.domain.timeframe import Timeframe
from tgk_trading.live.engine import LiveEngine
from tgk_trading.live.order_executor import RecordingOrderExecutor


class FakeAdapter:
  def get_candles(self, symbol, timeframe, count):
    return [Candle(
      time=datetime(2026, 9, 28, 10, 0),
      open=100.0,
      high=101.0,
      low=99.0,
      close=100.5
    )]


class BuyStrategy:
  def on_candle(self, data):
    return Signal(SignalType.BUY)


def test_live_engine_converts_buy_signal_to_market_order():
  executor = RecordingOrderExecutor()
  engine = LiveEngine(
    adapter=FakeAdapter(),
    symbol="XAUUSD",
    timeframe=Timeframe.M15,
    strategy=BuyStrategy(),
    order_executor=executor
  )

  engine.poll()

  assert len(executor.orders) == 1
  assert executor.orders[0].type == OrderType.MARKET
  assert executor.orders[0].side == OrderSide.BUY
  assert executor.orders[0].quantity == 1.0
