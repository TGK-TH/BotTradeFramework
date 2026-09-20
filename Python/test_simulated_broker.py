from tgk_trading.backtest.simulated_broker import SimulatedBroker
from tgk_trading.domain.order import Order, OrderSide, OrderType
from tgk_trading.domain.position import PositionSide


def test_execute_buy_order():
  broker = SimulatedBroker()

  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=1.0
  )

  position = broker.execute_order(
    order=order,
    price=2500.0
  )

  assert position.side == PositionSide.BUY
  assert position.quantity == 1.0
  assert position.entry_price == 2500.0


def test_execute_sell_order():
  broker = SimulatedBroker()

  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.SELL,
    quantity=2.0
  )

  position = broker.execute_order(
    order=order,
    price=2500.0
  )

  assert position.side == PositionSide.SELL
  assert position.quantity == 2.0
  assert position.entry_price == 2500.0


def test_close_buy_position():
  broker = SimulatedBroker()

  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=1.0
  )

  position = broker.execute_order(
    order=order,
    price=2500.0
  )

  closed = broker.close_position(
    position=position,
    price=2510.0
  )

  assert closed.position == position
  assert closed.exit_price == 2510.0
  assert closed.pnl == 10.0


def test_close_sell_position():
  broker = SimulatedBroker()

  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.SELL,
    quantity=1.0
  )

  position = broker.execute_order(
    order=order,
    price=2500.0
  )

  closed = broker.close_position(
    position=position,
    price=2490.0
  )

  assert closed.position == position
  assert closed.exit_price == 2490.0
  assert closed.pnl == 10.0


def run_tests():
  test_execute_buy_order()
  print("PASS: execute buy order")

  test_execute_sell_order()
  print("PASS: execute sell order")

  test_close_buy_position()
  print("PASS: close buy position")

  test_close_sell_position()
  print("PASS: close sell position")

  print()
  print("All SimulatedBroker tests passed")


if __name__ == "__main__":
  run_tests()
