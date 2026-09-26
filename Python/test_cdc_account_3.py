from datetime import datetime, timedelta

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.market_data import CandleSeries
from tgk_trading.domain.signal import SignalType
from tgk_trading.strategies.cdc_account_3 import CDCAccount3Strategy

def create_candle(time, close):
  return Candle(
    time=time,
    open=close,
    high=close,
    low=close,
    close=close,
  )

def test_insufficient_data():
  data = CandleSeries()
  strategy = CDCAccount3Strategy()

  time = datetime(2026, 1, 1)

  for i in range(26):
    data.append(create_candle(
      time + timedelta(minutes=i),
      100
    ))

  signal = strategy.on_candle(data)

  assert signal.type == SignalType.NONE

def test_no_cross():
  data = CandleSeries()
  strategy = CDCAccount3Strategy()

  time = datetime(2026, 1, 1)

  for i in range(50):
    data.append(create_candle(
      time + timedelta(minutes=i),
      100 + i
    ))

  signal = strategy.on_candle(data)

  assert signal.type == SignalType.NONE

def test_cross_up():
  data = CandleSeries()
  strategy = CDCAccount3Strategy()

  time = datetime(2026, 1, 1)

  prices = [100] * 30 + [200] * 30

  signals = []

  for i, price in enumerate(prices):
    data.append(create_candle(
      time + timedelta(minutes=i),
      price
    ))

    signal = strategy.on_candle(data)

    if signal.type != SignalType.NONE:
      signals.append(signal.type)

  assert SignalType.BUY in signals

def test_cross_down():
  data = CandleSeries()
  strategy = CDCAccount3Strategy()

  time = datetime(2026, 1, 1)

  prices = [100] * 30 + [200] * 30 + [50] * 30

  signals = []

  for i, price in enumerate(prices):
    data.append(create_candle(
      time + timedelta(minutes=i),
      price
    ))

    signal = strategy.on_candle(data)

    if signal.type != SignalType.NONE:
      signals.append(signal.type)

  assert SignalType.BUY in signals
  assert SignalType.SELL in signals

def run_tests():
  test_insufficient_data()
  print("PASS: insufficient data")

  test_no_cross()
  print("PASS: no cross")

  test_cross_up()
  print("PASS: cross up")

  test_cross_down()
  print("PASS: cross down")

  print()
  print("All CDC Account 3 tests passed")

if __name__ == "__main__":
  run_tests()
