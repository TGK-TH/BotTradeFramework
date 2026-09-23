from tgk_trading.backtest.result import BacktestResult


def format_backtest_report(result: BacktestResult) -> str:
  total_pnl = result.equity - result.initial_balance

  if result.initial_balance == 0:
    return_percent = 0.0
  else:
    return_percent = (total_pnl / result.initial_balance) * 100.0

  return (
    "Backtest Report\n"
    "===============\n"
    f"Initial Balance: {result.initial_balance:.2f}\n"
    f"Final Balance: {result.final_balance:.2f}\n"
    f"Realized P&L: {result.realized_pnl:.2f}\n"
    f"Unrealized P&L: {result.unrealized_pnl:.2f}\n"
    f"Equity: {result.equity:.2f}\n"
    f"Total P&L: {total_pnl:.2f}\n"
    f"Return: {return_percent:.2f}%\n"
    f"Max Drawdown: {result.max_drawdown:.2f}\n"
    f"Max Drawdown %: {result.max_drawdown_percent:.2f}%"
  )
