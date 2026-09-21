from tgk_trading.domain.account import Account
from tgk_trading.domain.position import Position, PositionSide


def test_initial_balance():
  account = Account(10000.0)

  assert account.balance() == 10000.0
  assert account.positions() == []


def test_add_position():
  account = Account(10000.0)

  position = Position(
    side=PositionSide.BUY,
    quantity=0.01,
    entry_price=2500.0,
  )

  account.add_position(position)
  positions = account.positions()

  assert len(positions) == 1
  assert positions[0] == position
  assert account.balance() == 10000.0


def test_remove_position():
  account = Account(10000.0)

  position = Position(
    side=PositionSide.BUY,
    quantity=0.01,
    entry_price=2500.0,
  )

  account.add_position(position)
  account.remove_position(position)

  assert account.positions() == []


def test_positions_returns_copy():
  account = Account(10000.0)

  position = Position(
    side=PositionSide.BUY,
    quantity=0.01,
    entry_price=2500.0,
  )

  account.add_position(position)
  positions = account.positions()
  positions.clear()

  assert len(account.positions()) == 1


def test_apply_realized_pnl():
  account = Account(10000.0)

  account.apply_realized_pnl(100.0)
  assert account.balance() == 10100.0

  account.apply_realized_pnl(-25.0)
  assert account.balance() == 10075.0


def run_tests():
  test_initial_balance()
  print("PASS: initial balance")

  test_add_position()
  print("PASS: add position")

  test_remove_position()
  print("PASS: remove position")

  test_positions_returns_copy()
  print("PASS: positions returns copy")

  test_apply_realized_pnl()
  print("PASS: apply realized P&L")

  print()
  print("All Account tests passed")


if __name__ == "__main__":
  run_tests()
