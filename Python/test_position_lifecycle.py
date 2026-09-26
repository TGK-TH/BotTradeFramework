from tgk_trading.domain.position import Position, PositionSide
from tgk_trading.domain.position_lifecycle import (
  ClosedPosition,
  PositionLifecycle
)

def test_close_buy_with_profit():
  position = Position(
    side=PositionSide.BUY,
    quantity=1.0,
    entry_price=2500.0
  )

  closed = PositionLifecycle.close(
    position=position,
    exit_price=2510.0
  )

  assert isinstance(closed, ClosedPosition)
  assert closed.position == position
  assert closed.exit_price == 2510.0
  assert closed.pnl == 10.0


def test_close_buy_with_loss():
  position = Position(
    side=PositionSide.BUY,
    quantity=1.0,
    entry_price=2500.0
  )

  closed = PositionLifecycle.close(
    position=position,
    exit_price=2490.0
  )

  assert closed.pnl == -10.0


def test_close_sell_with_profit():
  position = Position(
    side=PositionSide.SELL,
    quantity=1.0,
    entry_price=2500.0
  )

  closed = PositionLifecycle.close(
    position=position,
    exit_price=2490.0
  )

  assert closed.pnl == 10.0


def test_close_sell_with_loss():
  position = Position(
    side=PositionSide.SELL,
    quantity=1.0,
    entry_price=2500.0
  )

  closed = PositionLifecycle.close(
    position=position,
    exit_price=2510.0
  )

  assert closed.pnl == -10.0


def test_close_does_not_modify_position():
  position = Position(
    side=PositionSide.BUY,
    quantity=1.0,
    entry_price=2500.0
  )

  PositionLifecycle.close(
    position=position,
    exit_price=2510.0
  )

  assert position.side == PositionSide.BUY
  assert position.quantity == 1.0
  assert position.entry_price == 2500.0


def run_tests():
  test_close_buy_with_profit()
  print("PASS: close buy with profit")

  test_close_buy_with_loss()
  print("PASS: close buy with loss")

  test_close_sell_with_profit()
  print("PASS: close sell with profit")

  test_close_sell_with_loss()
  print("PASS: close sell with loss")

  test_close_does_not_modify_position()
  print("PASS: close does not modify position")

  print()
  print("All Position Lifecycle tests passed")


if __name__ == "__main__":
  run_tests()
