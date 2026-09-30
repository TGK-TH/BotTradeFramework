from tgk_trading.live.order_executor import MT5OrderRequestBuilder, MT5OrderExecutor


class FakeMT5:
  TRADE_ACTION_DEAL = 1
  ORDER_TYPE_BUY = 2
  ORDER_TYPE_SELL = 3
  POSITION_TYPE_BUY = 0
  POSITION_TYPE_SELL = 1
  ORDER_TIME_GTC = 4
  ORDER_FILLING_IOC = 5
  TRADE_RETCODE_DONE = 100


class Position:
  def __init__(self, ticket, symbol, position_type, volume, magic, comment):
    self.ticket = ticket
    self.symbol = symbol
    self.type = position_type
    self.volume = volume
    self.magic = magic
    self.comment = comment


def test_builder_closes_buy_with_sell_and_position_ticket():
  builder = MT5OrderRequestBuilder(FakeMT5())
  position = Position(1001, "XAUUSD", FakeMT5.POSITION_TYPE_BUY, 0.10, 4001, "TGK_PYTHON")

  request = builder.build_close_request(
    position=position,
    price=4143.05,
    magic=4001,
    comment="TGK_PYTHON"
  )

  assert request == {
    "action": 1,
    "symbol": "XAUUSD",
    "volume": 0.10,
    "type": FakeMT5.ORDER_TYPE_SELL,
    "position": 1001,
    "price": 4143.05,
    "deviation": 20,
    "magic": 4001,
    "comment": "TGK_PYTHON",
    "type_time": 4,
    "type_filling": 5
  }


def test_builder_closes_sell_with_buy_and_position_ticket():
  builder = MT5OrderRequestBuilder(FakeMT5())
  position = Position(1002, "XAUUSD", FakeMT5.POSITION_TYPE_SELL, 0.26, 4001, "TGK_PYTHON")

  request = builder.build_close_request(
    position=position,
    price=4143.41,
    magic=4001,
    comment="TGK_PYTHON"
  )

  assert request["type"] == FakeMT5.ORDER_TYPE_BUY
  assert request["volume"] == 0.26
  assert request["position"] == 1002
  assert request["price"] == 4143.41


def test_executor_builds_close_request_only_for_owned_position():
  class MT5(FakeMT5):
    class Tick:
      bid = 4143.05
      ask = 4143.41

    def symbol_info_tick(self, symbol):
      return self.Tick()

    def positions_get(self, symbol):
      return [
        Position(1001, "XAUUSD", self.POSITION_TYPE_BUY, 0.10, 4001, "TGK_PYTHON"),
        Position(1002, "XAUUSD", self.POSITION_TYPE_SELL, 0.26, 3003, "SELL"),
      ]

  executor = MT5OrderExecutor(
    MT5(),
    "XAUUSD",
    magic=4001,
    comment="TGK_PYTHON"
  )

  executor.close_position(1001)

  assert executor.get_last_request()["position"] == 1001
  assert executor.get_last_request()["type"] == FakeMT5.ORDER_TYPE_SELL
  assert executor.get_last_request()["price"] == 4143.05


def test_executor_closes_all_owned_positions_only():
  class MT5(FakeMT5):
    class Tick:
      bid = 4143.05
      ask = 4143.41

    def symbol_info_tick(self, symbol):
      return self.Tick()

    def positions_get(self, symbol):
      return [
        Position(1001, "XAUUSD", self.POSITION_TYPE_BUY, 0.10, 4001, "TGK_PYTHON"),
        Position(1002, "XAUUSD", self.POSITION_TYPE_SELL, 0.26, 3003, "SELL"),
        Position(1003, "XAUUSD", self.POSITION_TYPE_SELL, 0.20, 4001, "TGK_PYTHON"),
      ]

  executor = MT5OrderExecutor(
    MT5(),
    "XAUUSD",
    magic=4001,
    comment="TGK_PYTHON"
  )

  assert executor.close_owned_positions() == 2
  assert executor.get_last_request()["position"] == 1003


def test_executor_refuses_other_bot_position():
  class MT5(FakeMT5):
    def positions_get(self, symbol):
      return [
        Position(1002, "XAUUSD", self.POSITION_TYPE_SELL, 0.26, 3003, "SELL")
      ]

  executor = MT5OrderExecutor(
    MT5(),
    "XAUUSD",
    magic=4001,
    comment="TGK_PYTHON"
  )

  try:
    executor.close_position(1002)
    assert False, "Expected RuntimeError"
  except RuntimeError as error:
    assert "not owned" in str(error)
