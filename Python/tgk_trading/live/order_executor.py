from typing import Protocol

from tgk_trading.domain.order import Order, OrderSide, OrderType


class OrderExecutor(Protocol):
  def submit_order(self, order: Order) -> None:
    ...


class RecordingOrderExecutor:
  def __init__(self):
    self.orders: list[Order] = []

  def submit_order(self, order: Order) -> None:
    self.orders.append(order)


class MT5OrderRequestBuilder:
  def __init__(self, mt5_module):
    self._mt5 = mt5_module

  def build_market_request(
    self,
    order: Order,
    symbol: str,
    price: float,
    magic: int,
    comment: str
  ) -> dict:
    if order.type != OrderType.MARKET:
      raise ValueError(f"Unsupported order type: {order.type}")

    if order.quantity <= 0:
      raise ValueError("Order quantity must be greater than 0")

    if magic <= 0:
      raise ValueError("Magic number must be greater than 0")

    if not comment:
      raise ValueError("Order comment must not be empty")

    if order.side == OrderSide.BUY:
      order_type = self._mt5.ORDER_TYPE_BUY
    elif order.side == OrderSide.SELL:
      order_type = self._mt5.ORDER_TYPE_SELL
    else:
      raise ValueError(f"Unsupported order side: {order.side}")

    return {
      "action": self._mt5.TRADE_ACTION_DEAL,
      "symbol": symbol,
      "volume": order.quantity,
      "type": order_type,
      "price": price,
      "deviation": 20,
      "magic": magic,
      "comment": comment,
      "type_time": self._mt5.ORDER_TIME_GTC,
      "type_filling": self._mt5.ORDER_FILLING_IOC
    }


class MT5OrderExecutor:
  def __init__(
    self,
    mt5_module,
    symbol: str,
    magic: int,
    comment: str,
    live_trading: bool = False
  ):
    self._mt5 = mt5_module
    self._symbol = symbol
    self._magic = magic
    self._comment = comment
    self._builder = MT5OrderRequestBuilder(mt5_module)
    self._live_trading = live_trading
    self.last_request = None
    self.last_result = None

  def submit_order(self, order: Order) -> None:
    tick = self._mt5.symbol_info_tick(self._symbol)

    if tick is None:
      raise RuntimeError(
        f"Cannot get current tick for {self._symbol}: "
        f"{self._mt5.last_error()}"
      )

    price = tick.ask if order.side == OrderSide.BUY else tick.bid
    self.last_request = self._builder.build_market_request(
      order=order,
      symbol=self._symbol,
      price=price,
      magic=self._magic,
      comment=self._comment
    )

    if not self._live_trading:
      return

    self.last_result = self._mt5.order_send(self.last_request)

    if self.last_result is None:
      raise RuntimeError(
        f"MT5 order_send failed: {self._mt5.last_error()}"
      )

    if self.last_result.retcode != self._mt5.TRADE_RETCODE_DONE:
      raise RuntimeError(
        f"MT5 order rejected: retcode={self.last_result.retcode}"
      )

  def get_last_request(self):
    return self.last_request

  def get_last_result(self):
    return self.last_result
