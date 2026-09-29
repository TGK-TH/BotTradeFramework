from datetime import datetime, timedelta

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.signal import Signal, SignalType
from tgk_trading.domain.timeframe import Timeframe
from tgk_trading.live.engine import LiveEngine
from tgk_trading.live.order_executor import MT5OrderExecutor, RecordingOrderExecutor
from tgk_trading.strategies.cdc_account_3 import CDCAccount3Strategy


class FakeAdapter:
  def __init__(self, candle_batches):
    self.candle_batches = candle_batches
    self.calls = []

  def get_candles(self, symbol, timeframe, count):
    self.calls.append((symbol, timeframe, count))
    return self.candle_batches.pop(0)


class RecordingCDCStrategy:
  def __init__(self):
    self.strategy = CDCAccount3Strategy()
    self.signals = []

  def on_candle(self, data):
    signal = self.strategy.on_candle(data)
    self.signals.append(signal)
    return signal


class FakeStrategy:
  def __init__(self):
    self.candles = []

  def on_candle(self, data):
    self.candles.append(data.current())
    return Signal(SignalType.NONE)


def candle(minute):
  return Candle(
    time=datetime(2026, 9, 28, 10, minute),
    open=100.0,
    high=101.0,
    low=99.0,
    close=100.5
  )


def test_live_engine_processes_new_candles_only():
  adapter = FakeAdapter([
    [candle(0), candle(15), candle(30)],
    [candle(15), candle(30), candle(45)]
  ])
  strategy = FakeStrategy()
  engine = LiveEngine(
    adapter=adapter,
    symbol="XAUUSD",
    timeframe=Timeframe.M15,
    strategy=strategy,
    order_executor=RecordingOrderExecutor()
  )

  first = engine.poll()
  second = engine.poll()

  assert [item.time for item in first] == [
    datetime(2026, 9, 28, 10, 0),
    datetime(2026, 9, 28, 10, 15),
    datetime(2026, 9, 28, 10, 30)
  ]
  assert [item.time for item in second] == [
    datetime(2026, 9, 28, 10, 45)
  ]
  assert [item.time for item in strategy.candles] == [
    datetime(2026, 9, 28, 10, 0),
    datetime(2026, 9, 28, 10, 15),
    datetime(2026, 9, 28, 10, 30),
    datetime(2026, 9, 28, 10, 45)
  ]
  assert adapter.calls == [
    ("XAUUSD", Timeframe.M15, 100),
    ("XAUUSD", Timeframe.M15, 100)
  ]


def test_live_engine_passes_candle_series_to_strategy():
  adapter = FakeAdapter([[candle(0), candle(15)]])
  strategy = FakeStrategy()
  engine = LiveEngine(
    adapter=adapter,
    symbol="XAUUSD",
    timeframe=Timeframe.M15,
    strategy=strategy,
    order_executor=RecordingOrderExecutor()
  )

  engine.poll()

  assert len(strategy.candles) == 2
  assert strategy.candles[-1].time == datetime(2026, 9, 28, 10, 15)


def test_live_engine_can_run_cdc_strategy():
  prices = [100] * 30 + [200] * 30
  candles = [
    Candle(
      time=datetime(2026, 9, 28, 10) + timedelta(minutes=i),
      open=price,
      high=price,
      low=price,
      close=price
    )
    for i, price in enumerate(prices)
  ]
  adapter = FakeAdapter([candles])
  strategy = RecordingCDCStrategy()
  engine = LiveEngine(
    adapter=adapter,
    symbol="XAUUSD",
    timeframe=Timeframe.M15,
    strategy=strategy,
    order_executor=RecordingOrderExecutor()
  )

  engine.poll(count=60)

  assert len(strategy.signals) == 60
  assert any(signal.type.value == "BUY" for signal in strategy.signals)


def test_live_engine_end_to_end_creates_mt5_request():
  class FakeMT5:
    TRADE_ACTION_DEAL = 1
    ORDER_TYPE_BUY = 2
    ORDER_TYPE_SELL = 3
    ORDER_TIME_GTC = 4
    ORDER_FILLING_IOC = 5

    class Tick:
      ask = 4050.25
      bid = 4050.05

    def symbol_info_tick(self, symbol):
      assert symbol == "XAUUSD"
      return self.Tick()

  class BuyStrategy:
    def on_candle(self, data):
      return Signal(SignalType.BUY)

  adapter = FakeAdapter([[candle(0)]])
  executor = MT5OrderExecutor(FakeMT5(), "XAUUSD", magic=4001, comment="TGK_PYTHON")
  engine = LiveEngine(
    adapter=adapter,
    symbol="XAUUSD",
    timeframe=Timeframe.M15,
    strategy=BuyStrategy(),
    order_executor=executor
  )

  engine.poll()

  assert executor.get_last_request() == {
    "action": 1,
    "symbol": "XAUUSD",
    "volume": 1.0,
    "type": 2,
    "price": 4050.25,
    "deviation": 20,
    "magic": 4001,
    "comment": "TGK_PYTHON",
    "type_time": 4,
    "type_filling": 5
  }


def test_live_engine_tracks_last_processed_candle():
  adapter = FakeAdapter([[candle(0), candle(15)]])
  strategy = FakeStrategy()
  engine = LiveEngine(
    adapter=adapter,
    symbol="XAUUSD",
    timeframe=Timeframe.M15,
    strategy=strategy,
    order_executor=RecordingOrderExecutor()
  )

  engine.poll()

  assert engine.last_processed_time() == datetime(2026, 9, 28, 10, 15)
