from tgk_trading.domain.pnl import calculate_pnl
from tgk_trading.domain.position import PositionSide

def test_buy_profit():
  pnl = calculate_pnl(
    side=PositionSide.BUY,
    entry_price=2500.0,
    exit_price=2510.0,
    quantity=1.0,
  )

  assert pnl == 10.0

def test_buy_loss():
  pnl = calculate_pnl(
    side=PositionSide.BUY,
    entry_price=2500.0,
    exit_price=2490.0,
    quantity=1.0,
  )

  assert pnl == -10.0

def test_sell_profit():
  pnl = calculate_pnl(
    side=PositionSide.SELL,
    entry_price=2500.0,
    exit_price=2490.0,
    quantity=1.0,
  )

  assert pnl == 10.0

def test_sell_loss():
  pnl = calculate_pnl(
    side=PositionSide.SELL,
    entry_price=2500.0,
    exit_price=2510.0,
    quantity=1.0,
  )

  assert pnl == -10.0

def test_zero_pnl():
  buy_pnl = calculate_pnl(
    side=PositionSide.BUY,
    entry_price=2500.0,
    exit_price=2500.0,
    quantity=1.0,
  )

  sell_pnl = calculate_pnl(
    side=PositionSide.SELL,
    entry_price=2500.0,
    exit_price=2500.0,
    quantity=1.0,
  )

  assert buy_pnl == 0.0
  assert sell_pnl == 0.0

def test_quantity():
  pnl = calculate_pnl(
    side=PositionSide.BUY,
    entry_price=2500.0,
    exit_price=2510.0,
    quantity=2.5,
  )

  assert pnl == 25.0

def run_tests():
  test_buy_profit()
  print("PASS: buy profit")

  test_buy_loss()
  print("PASS: buy loss")

  test_sell_profit()
  print("PASS: sell profit")

  test_sell_loss()
  print("PASS: sell loss")

  test_zero_pnl()
  print("PASS: zero P&L")

  test_quantity()
  print("PASS: quantity")

  print()
  print("All P&L tests passed")

if __name__ == "__main__":
  run_tests()
