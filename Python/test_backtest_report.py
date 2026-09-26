from datetime import datetime
from tgk_trading.backtest.report import format_backtest_report
from tgk_trading.backtest.trade_statistics import TradeStatistics
from tgk_trading.domain.position import PositionSide
from tgk_trading.domain.trade import Trade
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
    trades=[],
    trade_statistics=TradeStatistics(
      total_trades=0,
      winning_trades=0,
      losing_trades=0,
      win_rate=0.0,
      gross_profit=0.0,
      gross_loss=0.0,
      profit_factor=0.0,
      average_trade=0.0
    )
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
    "Max Drawdown %: 1.00%\n"
    "\n"
    "Trade Statistics\n"
    "-----------------\n"
    "Total Trades: 0\n"
    "Winning Trades: 0\n"
    "Losing Trades: 0\n"
    "Win Rate: 0.00%\n"
    "Gross Profit: 0.00\n"
    "Gross Loss: 0.00\n"
    "Profit Factor: 0.00\n"
    "Average Trade: 0.00\n"
    "\n"
    "Trade History\n"
    "------------"
  )


def test_format_backtest_report_with_trade_history():
  trades = [
    Trade(
      side=PositionSide.BUY,
      quantity=1.0,
      entry_time=datetime(2026, 1, 1, 10, 0),
      entry_price=2500.0,
      exit_time=datetime(2026, 1, 1, 11, 0),
      exit_price=2510.0,
      pnl=10.0
    ),
    Trade(
      side=PositionSide.SELL,
      quantity=2.0,
      entry_time=datetime(2026, 1, 2, 10, 0),
      entry_price=2520.0,
      exit_time=datetime(2026, 1, 2, 11, 0),
      exit_price=2530.0,
      pnl=-20.0
    )
  ]

  result = BacktestResult(
    initial_balance=10000.0,
    final_balance=9990.0,
    realized_pnl=-10.0,
    unrealized_pnl=0.0,
    equity=9990.0,
    equity_curve=[10000.0, 10010.0, 9990.0],
    max_drawdown=20.0,
    max_drawdown_percent=0.1998001998001998,
    trades=trades,
    trade_statistics=TradeStatistics(
      total_trades=2,
      winning_trades=1,
      losing_trades=1,
      win_rate=50.0,
      gross_profit=10.0,
      gross_loss=20.0,
      profit_factor=0.5,
      average_trade=-5.0
    )
  )

  report = format_backtest_report(result)

  assert report == (
    "Backtest Report\n"
    "===============\n"
    "Initial Balance: 10000.00\n"
    "Final Balance: 9990.00\n"
    "Realized P&L: -10.00\n"
    "Unrealized P&L: 0.00\n"
    "Equity: 9990.00\n"
    "Total P&L: -10.00\n"
    "Return: -0.10%\n"
    "Max Drawdown: 20.00\n"
    "Max Drawdown %: 0.20%\n"
    "\n"
    "Trade Statistics\n"
    "-----------------\n"
    "Total Trades: 2\n"
    "Winning Trades: 1\n"
    "Losing Trades: 1\n"
    "Win Rate: 50.00%\n"
    "Gross Profit: 10.00\n"
    "Gross Loss: 20.00\n"
    "Profit Factor: 0.50\n"
    "Average Trade: -5.00\n"
    "\n"
    "Trade History\n"
    "------------\n"
    "Trade #1: BUY Entry=2026-01-01 10:00:00 @ 2500.00 Exit=2026-01-01 11:00:00 @ 2510.00 Quantity=1.00 P&L=10.00\n"
    "Trade #2: SELL Entry=2026-01-02 10:00:00 @ 2520.00 Exit=2026-01-02 11:00:00 @ 2530.00 Quantity=2.00 P&L=-20.00"
  )


def run_tests():
  test_format_backtest_report()
  print("PASS: backtest report")

  test_format_backtest_report_with_trade_history()
  print("PASS: backtest report with trade history")
  print()
  print("All Backtest Report tests passed")


if __name__ == "__main__":
  run_tests()
