from tgk_trading.domain.pnl import calculate_unrealized_pnl
from tgk_trading.domain.position import PositionSide


def test_buy_profit():
  pnl = calculate_unrealized_pnl(
    side=PositionSide.BUY,
    entry_price=2500.0,
    current_price=2510.0,
    quantity=1.0
  )

  assert pnl == 10.0


def test_buy_loss():
  pnl = calculate_unrealized_pnl(
    side=PositionSide.BUY,
    entry_price=2500.0,
    current_price=2490.0,
    quantity=1.0
  )

  assert pnl == -10.0


def test_sell_profit():
  pnl = calculate_unrealized_pnl(
    side=PositionSide.SELL,
    entry_price=2500.0,
    current_price=2490.0,
    quantity=1.0
  )

  assert pnl == 10.0


def test_sell_loss():
  pnl = calculate_unrealized_pnl(
    side=PositionSide.SELL,
    entry_price=2500.0,
    current_price=2510.0,
    quantity=1.0
  )

  assert pnl == -10.0


def test_quantity():
  pnl = calculate_unrealized_pnl(
    side=PositionSide.BUY,
    entry_price=2500.0,
    current_price=2510.0,
    quantity=2.0
  )

  assert pnl == 20.0


def run_tests():
  test_buy_profit()
  test_buy_loss()
  test_sell_profit()
  test_sell_loss()
  test_quantity()

  print("PASS: unrealized P&L")

  print()
  print("All Unrealized P&L tests passed")


if __name__ == "__main__":
  run_tests()
