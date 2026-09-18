from tgk_trading.domain.order import Order, OrderSide, OrderType

def test_market_buy_order():
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=0.01,
  )

  assert order.type == OrderType.MARKET
  assert order.side == OrderSide.BUY
  assert order.quantity == 0.01

def test_market_sell_order():
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.SELL,
    quantity=0.02,
  )

  assert order.type == OrderType.MARKET
  assert order.side == OrderSide.SELL
  assert order.quantity == 0.02

def run_tests():
  test_market_buy_order()
  print("PASS: market buy order")

  test_market_sell_order()
  print("PASS: market sell order")

  print()
  print("All Order tests passed")

if __name__ == "__main__":
  run_tests()
