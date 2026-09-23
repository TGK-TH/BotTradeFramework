from tgk_trading.backtest.report import format_backtest_report
from tgk_trading.backtest.result import BacktestResult


def test_format_backtest_report():
  result = BacktestResult(
    initial_balance=10000.0,
    final_balance=9950.0,
    realized_pnl=-50.0,
    unrealized_pnl=0.0,
    equity=9950.0,
    equity_curve=[10000.0, 10050.0, 9950.0],
    max_drawdown=100.0,
    max_drawdown_percent=0.9950248756218906,
    trades=[]
  )

  report = format_backtest_report(result)

  assert report == (
    "Backtest Report\n"
    "===============\n"
    "Initial Balance: 10000.00\n"
    "Final Balance: 9950.00\n"
    "Realized P&L: -50.00\n"
    "Unrealized P&L: 0.00\n"
    "Equity: 9950.00\n"
    "Total P&L: -50.00\n"
    "Return: -0.50%\n"
    "Max Drawdown: 100.00\n"
    "Max Drawdown %: 1.00%"
  )


def run_tests():
  test_format_backtest_report()
  print("PASS: backtest report")
  print()
  print("All Backtest Report tests passed")


if __name__ == "__main__":
  run_tests()
