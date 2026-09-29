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
  class FakeMT5:
    TRADE_ACTION_DEAL = 1
    ORDER_TYPE_BUY = 2
    ORDER_TYPE_SELL = 3
    ORDER_TIME_GTC = 4
    ORDER_FILLING_IOC = 5
    TRADE_RETCODE_DONE = 100

    class Tick:
      ask = 4050.25
      bid = 4050.05

    def symbol_info_tick(self, symbol):
      assert symbol == "XAUUSD"
      return self.Tick()

    def order_send(self, request):
      raise AssertionError("order_send must not be called in safe mode")

  executor = MT5OrderExecutor(FakeMT5(), "XAUUSD", magic=4001, comment="TGK_PYTHON")
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
    "magic": 4001,
    "comment": "TGK_PYTHON",
    "type_time": 4,
    "type_filling": 5
  }
  assert executor.get_last_result() is None


def test_mt5_order_executor_sends_when_live_trading_enabled():
  class FakeMT5:
    TRADE_ACTION_DEAL = 1
    ORDER_TYPE_BUY = 2
    ORDER_TYPE_SELL = 3
    ORDER_TIME_GTC = 4
    ORDER_FILLING_IOC = 5
    TRADE_RETCODE_DONE = 100

    class Tick:
      ask = 4050.25
      bid = 4050.05

    class Result:
      retcode = 100

    def __init__(self):
      self.sent_requests = []

    def symbol_info_tick(self, symbol):
      return self.Tick()

    def order_send(self, request):
      self.sent_requests.append(request)
      return self.Result()

    def last_error(self):
      return "fake error"

  mt5 = FakeMT5()
  executor = MT5OrderExecutor(mt5, "XAUUSD", magic=4001, comment="TGK_PYTHON", live_trading=True)
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.SELL,
    quantity=0.01
  )

  executor.submit_order(order)

  assert len(mt5.sent_requests) == 1
  assert mt5.sent_requests[0]["type"] == mt5.ORDER_TYPE_SELL
  assert mt5.sent_requests[0]["price"] == 4050.05
  assert executor.get_last_result().retcode == mt5.TRADE_RETCODE_DONE


def test_mt5_order_executor_rejects_failed_result():
  class FakeMT5:
    TRADE_ACTION_DEAL = 1
    ORDER_TYPE_BUY = 2
    ORDER_TIME_GTC = 4
    ORDER_FILLING_IOC = 5
    TRADE_RETCODE_DONE = 100

    class Tick:
      ask = 4050.25
      bid = 4050.05

    class Result:
      retcode = 999

    def symbol_info_tick(self, symbol):
      return self.Tick()

    def order_send(self, request):
      return self.Result()

    def last_error(self):
      return "fake error"

  executor = MT5OrderExecutor(FakeMT5(), "XAUUSD", magic=4001, comment="TGK_PYTHON", live_trading=True)
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=0.01
  )

  try:
    executor.submit_order(order)
    assert False, "Expected RuntimeError"
  except RuntimeError as error:
    assert "MT5 order rejected" in str(error)


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
    price=4000.50,
    magic=4001,
    comment="TGK_PYTHON"
  )

  assert request == {
    "action": FakeMT5.TRADE_ACTION_DEAL,
    "symbol": "XAUUSD",
    "volume": 0.01,
    "type": FakeMT5.ORDER_TYPE_BUY,
    "price": 4000.50,
    "deviation": 20,
    "magic": 4001,
    "comment": "TGK_PYTHON",
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
    price=4000.50,
    magic=4001,
    comment="TGK_PYTHON"
  )

  assert request["type"] == FakeMT5.ORDER_TYPE_SELL
  assert request["volume"] == 0.01
  assert request["symbol"] == "XAUUSD"
  assert request["magic"] == 4001
  assert request["comment"] == "TGK_PYTHON"


def test_mt5_order_request_builder_rejects_invalid_quantity():
  builder = MT5OrderRequestBuilder(FakeMT5())
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=0
  )

  try:
    builder.build_market_request(
      order,
      "XAUUSD",
      4000.50,
      magic=4001,
      comment="TGK_PYTHON"
    )
    assert False
  except ValueError as error:
    assert str(error) == "Order quantity must be greater than 0"
