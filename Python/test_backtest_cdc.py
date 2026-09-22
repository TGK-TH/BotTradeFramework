from datetime import datetime, timedelta

from tgk_trading.backtest.engine import BacktestEngine
from tgk_trading.domain.candle import Candle
from tgk_trading.strategies.cdc_account_3 import CDCAccount3Strategy


def create_candles():
  prices = (
    [100.0] * 30
    + [200.0] * 30
    + [250.0] * 30
    + [150.0] * 30
  )

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


def test_backtest_cdc():
  strategy = CDCAccount3Strategy()

  engine = BacktestEngine(
    strategy=strategy,
    initial_balance=10000.0
  )

  result = engine.run(create_candles())

  assert result.initial_balance == 10000.0
  assert result.realized_pnl == -50.0
  assert result.final_balance == 9950.0
  assert result.unrealized_pnl == 0.0
  assert result.equity == 9950.0
  assert result.max_drawdown == 100.0


def run_tests():
  test_backtest_cdc()

  print("PASS: CDC Account 3 end-to-end backtest")

  print()
  print("All CDC Account 3 backtest tests passed")


if __name__ == "__main__":
  run_tests()
