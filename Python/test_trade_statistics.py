from tgk_trading.backtest.trade_statistics import calculate_trade_statistics
from tgk_trading.domain.position import Position, PositionSide
from tgk_trading.domain.trade import Trade


def create_trade(pnl: float) -> Trade:
  return Trade(
    position=Position(
      side=PositionSide.BUY,
      quantity=1.0,
      entry_price=100.0
    ),
    exit_price=100.0 + pnl,
    pnl=pnl
  )


def test_trade_statistics():
  trades = [
    create_trade(100.0),
    create_trade(-50.0),
    create_trade(25.0),
    create_trade(-25.0)
  ]

  stats = calculate_trade_statistics(trades)

  assert stats.total_trades == 4
  assert stats.winning_trades == 2
  assert stats.losing_trades == 2
  assert stats.win_rate == 50.0
  assert stats.gross_profit == 125.0
  assert stats.gross_loss == 75.0
  assert stats.profit_factor == 125.0 / 75.0
  assert stats.average_trade == 12.5


def test_empty_trades():
  stats = calculate_trade_statistics([])

  assert stats.total_trades == 0
  assert stats.winning_trades == 0
  assert stats.losing_trades == 0
  assert stats.win_rate == 0.0
  assert stats.gross_profit == 0.0
  assert stats.gross_loss == 0.0
  assert stats.profit_factor == 0.0
  assert stats.average_trade == 0.0


def test_all_winning_trades():
  stats = calculate_trade_statistics([
    create_trade(100.0),
    create_trade(50.0)
  ])

  assert stats.win_rate == 100.0
  assert stats.gross_profit == 150.0
  assert stats.gross_loss == 0.0
  assert stats.profit_factor == float("inf")


def test_all_losing_trades():
  stats = calculate_trade_statistics([
    create_trade(-100.0),
    create_trade(-50.0)
  ])

  assert stats.win_rate == 0.0
  assert stats.gross_profit == 0.0
  assert stats.gross_loss == 150.0
  assert stats.profit_factor == 0.0


def test_breakeven_trade():
  stats = calculate_trade_statistics([
    create_trade(0.0)
  ])

  assert stats.total_trades == 1
  assert stats.winning_trades == 0
  assert stats.losing_trades == 0
  assert stats.win_rate == 0.0
  assert stats.gross_profit == 0.0
  assert stats.gross_loss == 0.0
  assert stats.profit_factor == 0.0
  assert stats.average_trade == 0.0


def run_tests():
  test_trade_statistics()
  print("PASS: trade statistics")

  test_empty_trades()
  print("PASS: empty trades")

  test_all_winning_trades()
  print("PASS: all winning trades")

  test_all_losing_trades()
  print("PASS: all losing trades")

  test_breakeven_trade()
  print("PASS: breakeven trade")

  print()
  print("All Trade Statistics tests passed")


if __name__ == "__main__":
  run_tests()
