from datetime import datetime

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.timeframe import Timeframe
from tgk_trading.live.engine import LiveEngine


class FakeAdapter:
  def __init__(self, candle_batches):
    self.candle_batches = candle_batches
    self.calls = []

  def get_candles(self, symbol, timeframe, count):
    self.calls.append((symbol, timeframe, count))
    return self.candle_batches.pop(0)


class FakeStrategy:
  def __init__(self):
    self.candles = []

  def on_candle(self, candle):
    self.candles.append(candle)


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
    strategy=strategy
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


def test_live_engine_tracks_last_processed_candle():
  adapter = FakeAdapter([[candle(0), candle(15)]])
  strategy = FakeStrategy()
  engine = LiveEngine(
    adapter=adapter,
    symbol="XAUUSD",
    timeframe=Timeframe.M15,
    strategy=strategy
  )

  engine.poll()

  assert engine.last_processed_time() == datetime(2026, 9, 28, 10, 15)
