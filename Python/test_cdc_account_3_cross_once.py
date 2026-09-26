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

def collect_signals(prices):
  data = CandleSeries()
  strategy = CDCAccount3Strategy()

  start_time = datetime(2026, 1, 1)
  signals = []

  for i, price in enumerate(prices):
    data.append(create_candle(
      start_time + timedelta(minutes=i),
      price
    ))

    signal = strategy.on_candle(data)
    signals.append(signal.type)

  return signals

def test_cross_up_occurs_once():
  prices = [100] * 30 + [200] * 30

  signals = collect_signals(prices)

  buy_indexes = [
    i
    for i, signal in enumerate(signals)
    if signal == SignalType.BUY
  ]

  assert len(buy_indexes) == 1

  buy_index = buy_indexes[0]

  assert buy_index > 0

  assert signals[buy_index - 1] == SignalType.NONE
  assert signals[buy_index] == SignalType.BUY
  assert signals[buy_index + 1] == SignalType.NONE

def test_cross_down_occurs_once():
  prices = [100] * 30 + [200] * 30 + [50] * 30

  signals = collect_signals(prices)

  sell_indexes = [
    i
    for i, signal in enumerate(signals)
    if signal == SignalType.SELL
  ]

  assert len(sell_indexes) == 1

  sell_index = sell_indexes[0]

  assert sell_index > 0

  assert signals[sell_index - 1] == SignalType.NONE
  assert signals[sell_index] == SignalType.SELL
  assert signals[sell_index + 1] == SignalType.NONE

def test_cross_up_and_down_each_occur_once():
  prices = [100] * 30 + [200] * 30 + [50] * 30

  signals = collect_signals(prices)

  buy_indexes = [
    i
    for i, signal in enumerate(signals)
    if signal == SignalType.BUY
  ]

  sell_indexes = [
    i
    for i, signal in enumerate(signals)
    if signal == SignalType.SELL
  ]

  assert len(buy_indexes) == 1
  assert len(sell_indexes) == 1

  assert buy_indexes[0] < sell_indexes[0]

def run_tests():
  test_cross_up_occurs_once()
  print("PASS: cross up occurs once")

  test_cross_down_occurs_once()
  print("PASS: cross down occurs once")

  test_cross_up_and_down_each_occur_once()
  print("PASS: cross up and down each occur once")

  print()
  print("All CDC Account 3 cross-once tests passed")

if __name__ == "__main__":
  run_tests()
