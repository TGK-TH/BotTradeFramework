from tgk_trading.domain.order import Order, OrderSide, OrderType
from tgk_trading.live.order_executor import RecordingOrderExecutor
from tgk_trading.live.order_executor import MT5OrderRequestBuilder, MT5OrderExecutor


class FakeMT5:
  TRADE_ACTION_DEAL = 1
  ORDER_TYPE_BUY = 2
  ORDER_TYPE_SELL = 3
  ORDER_TIME_GTC = 4
  ORDER_FILLING_IOC = 5

  class Tick:
    ask = 4050.25
    bid = 4050.05

  def symbol_info_tick(self, symbol):
    assert symbol == "XAUUSD"
    return self.Tick()


def test_recording_order_executor_records_orders():
  executor = RecordingOrderExecutor()
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=1.0
  )

  executor.submit_order(order)

  assert executor.orders == [order]


def test_mt5_order_executor_builds_request_without_sending():
  executor = MT5OrderExecutor(FakeMT5(), "XAUUSD")
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=0.01
  )

  executor.submit_order(order)

  assert executor.get_last_request() == {
    "action": 1,
    "symbol": "XAUUSD",
    "volume": 0.01,
    "type": 2,
    "price": 4050.25,
    "deviation": 20,
    "type_time": 4,
    "type_filling": 5
  }


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
