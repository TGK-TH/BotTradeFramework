from tgk_trading.domain.position import Position, PositionSide

def test_buy_position():
  position = Position(
    side=PositionSide.BUY,
    quantity=0.01,
    entry_price=2500.0,
  )

  assert position.side == PositionSide.BUY
  assert position.quantity == 0.01
  assert position.entry_price == 2500.0

def test_sell_position():
  position = Position(
    side=PositionSide.SELL,
    quantity=0.02,
    entry_price=2510.0,
  )

  assert position.side == PositionSide.SELL
  assert position.quantity == 0.02
  assert position.entry_price == 2510.0

def run_tests():
  test_buy_position()
  print("PASS: buy position")

  test_sell_position()
  print("PASS: sell position")

  print()
  print("All Position tests passed")

if __name__ == "__main__":
  run_tests()
