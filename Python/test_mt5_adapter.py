from datetime import datetime, timezone

from tgk_trading.brokers.mt5 import MT5Adapter
from tgk_trading.domain.timeframe import Timeframe


class FakeMT5:
  TIMEFRAME_M15 = 15

  def __init__(self, initialize_result=True, rates=None):
    self.initialize_result = initialize_result
    self.rates = rates
    self.initialize_calls = 0
    self.shutdown_calls = 0
    self.copy_rates_calls = []

  def initialize(self):
    self.initialize_calls += 1
    return self.initialize_result

  def shutdown(self):
    self.shutdown_calls += 1

  def last_error(self):
    return (10000, "Fake error")

  def copy_rates_from_pos(self, symbol, timeframe, start_pos, count):
    self.copy_rates_calls.append(
      (symbol, timeframe, start_pos, count)
    )
    return self.rates


def test_connect_initializes_mt5():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)

  adapter.connect()

  assert adapter.is_connected()
  assert mt5.initialize_calls == 1


def test_connect_does_not_initialize_twice():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)

  adapter.connect()
  adapter.connect()

  assert mt5.initialize_calls == 1


def test_disconnect_shuts_down_mt5():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)

  adapter.connect()
  adapter.disconnect()

  assert not adapter.is_connected()
  assert mt5.shutdown_calls == 1


def test_disconnect_does_nothing_when_not_connected():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)

  adapter.disconnect()

  assert mt5.shutdown_calls == 0


def test_connect_raises_when_mt5_initialize_fails():
  mt5 = FakeMT5(initialize_result=False)
  adapter = MT5Adapter(mt5)

  try:
    adapter.connect()
    assert False, "Expected RuntimeError"
  except RuntimeError as error:
    assert "MT5 initialize failed" in str(error)


def test_get_candles_returns_closed_candles():
  mt5 = FakeMT5(rates=[
    {
      "time": 1758794400,
      "open": 3800.0,
      "high": 3810.0,
      "low": 3795.0,
      "close": 3805.0
    },
    {
      "time": 1758795300,
      "open": 3805.0,
      "high": 3815.0,
      "low": 3800.0,
      "close": 3812.0
    }
  ])
  adapter = MT5Adapter(mt5)
  adapter.connect()

  candles = adapter.get_candles("XAUUSD", Timeframe.M15, 2)

  assert len(candles) == 2
  assert candles[0].time == datetime.fromtimestamp(1758794400, tz=timezone.utc).replace(tzinfo=None)
  assert candles[0].open == 3800.0
  assert candles[1].close == 3812.0
  assert mt5.copy_rates_calls == [("XAUUSD", 15, 1, 2)]


def test_get_candles_requires_connection():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)

  try:
    adapter.get_candles("XAUUSD", Timeframe.M15, 10)
    assert False, "Expected RuntimeError"
  except RuntimeError as error:
    assert "MT5 is not connected" in str(error)


def test_get_candles_requires_positive_count():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)
  adapter.connect()

  try:
    adapter.get_candles("XAUUSD", Timeframe.M15, 0)
    assert False, "Expected ValueError"
  except ValueError as error:
    assert "count must be greater than 0" in str(error)


def test_get_candles_raises_when_mt5_returns_none():
  mt5 = FakeMT5(rates=None)
  adapter = MT5Adapter(mt5)
  adapter.connect()

  try:
    adapter.get_candles("XAUUSD", Timeframe.M15, 10)
    assert False, "Expected RuntimeError"
  except RuntimeError as error:
    assert "MT5 failed to get candles" in str(error)
