from tgk_trading.domain.order import Order, OrderSide, OrderType
from tgk_trading.live.order_executor import RecordingOrderExecutor
from tgk_trading.live.order_executor import MT5OrderRequestBuilder

def test_recording_order_executor_records_orders():
  executor = RecordingOrderExecutor()
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=1.0
  )

  executor.submit_order(order)

  assert executor.orders == [order]


class FakeMT5:
  TRADE_ACTION_DEAL = 1
  ORDER_TYPE_BUY = 2
  ORDER_TYPE_SELL = 3
  ORDER_TIME_GTC = 4
  ORDER_FILLING_IOC = 5


def test_mt5_order_request_builder_maps_buy_order():
  builder = MT5OrderRequestBuilder(FakeMT5())
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=0.01
  )

  request = builder.build_market_request(
    order,
    symbol="XAUUSD",
    price=4000.50
  )

  assert request == {
    "action": FakeMT5.TRADE_ACTION_DEAL,
    "symbol": "XAUUSD",
    "volume": 0.01,
    "type": FakeMT5.ORDER_TYPE_BUY,
    "price": 4000.50,
    "deviation": 20,
    "type_time": FakeMT5.ORDER_TIME_GTC,
    "type_filling": FakeMT5.ORDER_FILLING_IOC
  }


def test_mt5_order_request_builder_maps_sell_order():
  builder = MT5OrderRequestBuilder(FakeMT5())
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.SELL,
    quantity=0.01
  )

  request = builder.build_market_request(
    order,
    symbol="XAUUSD",
    price=4000.50
  )

  assert request["type"] == FakeMT5.ORDER_TYPE_SELL
  assert request["volume"] == 0.01
  assert request["symbol"] == "XAUUSD"


def test_mt5_order_request_builder_rejects_invalid_quantity():
  builder = MT5OrderRequestBuilder(FakeMT5())
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=0
  )

  try:
    builder.build_market_request(order, "XAUUSD", 4000.50)
    assert False
  except ValueError as error:
    assert str(error) == "Order quantity must be greater than 0"
