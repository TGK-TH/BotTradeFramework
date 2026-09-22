from dataclasses import FrozenInstanceError

from tgk_trading.backtest.result import BacktestResult


def test_backtest_result():
  result = BacktestResult(
    initial_balance=10000.0,
    final_balance=10150.0,
    realized_pnl=150.0,
    unrealized_pnl=0.0,
    equity=10150.0,
    equity_curve=[10000.0, 10050.0, 10100.0, 10150.0],
    max_drawdown=0.0
  )

  assert result.initial_balance == 10000.0
  assert result.final_balance == 10150.0
  assert result.realized_pnl == 150.0
  assert result.unrealized_pnl == 0.0
  assert result.equity == 10150.0
  assert result.equity_curve == [10000.0, 10050.0, 10100.0, 10150.0]
  assert result.max_drawdown == 0.0


def test_backtest_result_is_immutable():
  result = BacktestResult(
    initial_balance=10000.0,
    final_balance=10150.0,
    realized_pnl=150.0,
    unrealized_pnl=0.0,
    equity=10150.0,
    equity_curve=[10000.0, 10050.0, 10100.0, 10150.0],
    max_drawdown=0.0
  )

  try:
    result.final_balance = 999999.0
    assert False
  except FrozenInstanceError:
    pass


def run_tests():
  test_backtest_result()
  print("PASS: backtest result")

  test_backtest_result_is_immutable()
  print("PASS: backtest result is immutable")

  print()
  print("All BacktestResult tests passed")


if __name__ == "__main__":
  run_tests()
