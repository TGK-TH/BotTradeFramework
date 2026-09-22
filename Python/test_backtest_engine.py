from datetime import datetime, timedelta

from tgk_trading.backtest.engine import BacktestEngine
from tgk_trading.domain.candle import Candle
from tgk_trading.domain.signal import Signal, SignalType
from tgk_trading.strategies.base import Strategy


class TestStrategy(Strategy):

  def __init__(self):
    self._count = 0

  def on_candle(self, data):
    self._count += 1

    if self._count == 1:
      return Signal(SignalType.BUY)

    if self._count == 3:
      return Signal(SignalType.SELL)

    return Signal(SignalType.NONE)


def create_candles():
  prices = [
    2500.0,
    2505.0,
    2510.0,
    2500.0
  ]

  start_time = datetime(2026, 1, 1)

  candles = []

  for i, price in enumerate(prices):
    candles.append(
      Candle(
        time=start_time + timedelta(minutes=i),
        open=price,
        high=price,
        low=price,
        close=price
      )
    )

  return candles


def test_backtest_engine():
  strategy = TestStrategy()

  engine = BacktestEngine(
    strategy=strategy,
    initial_balance=10000.0
  )

  result = engine.run(create_candles())

  assert result.initial_balance == 10000.0
  assert result.realized_pnl == 10.0
  assert result.final_balance == 10010.0
  assert result.unrealized_pnl == 10.0
  assert result.equity == 10020.0


def run_tests():
  test_backtest_engine()
  print("PASS: backtest engine")

  print()
  print("All Backtest Engine tests passed")


if __name__ == "__main__":
  run_tests()
