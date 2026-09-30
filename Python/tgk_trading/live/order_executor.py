from typing import Protocol

from tgk_trading.domain.order import Order, OrderSide, OrderType


class OrderExecutor(Protocol):
  def submit_order(self, order: Order) -> None:
    ...

  def close_owned_positions(self) -> int:
    ...


class RecordingOrderExecutor:
  def __init__(self):
    self.orders: list[Order] = []

  def submit_order(self, order: Order) -> None:
    self.orders.append(order)

  def close_owned_positions(self) -> int:
    return 0


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

  def build_close_request(
    self,
    position,
    price: float,
    magic: int,
    comment: str
  ) -> dict:
    if position.volume <= 0:
      raise ValueError("Position volume must be greater than 0")

    if magic <= 0:
      raise ValueError("Magic number must be greater than 0")

    if not comment:
      raise ValueError("Order comment must not be empty")

    if position.type == self._mt5.POSITION_TYPE_BUY:
      order_type = self._mt5.ORDER_TYPE_SELL
    elif position.type == self._mt5.POSITION_TYPE_SELL:
      order_type = self._mt5.ORDER_TYPE_BUY
    else:
      raise ValueError(f"Unsupported position type: {position.type}")

    return {
      "action": self._mt5.TRADE_ACTION_DEAL,
      "symbol": position.symbol,
      "volume": position.volume,
      "type": order_type,
      "position": position.ticket,
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

  def get_owned_positions(self):
    positions = self._mt5.positions_get(symbol=self._symbol)

    if positions is None:
      raise RuntimeError(
        f"MT5 positions_get failed: {self._mt5.last_error()}"
      )

    return [
      position
      for position in positions
      if position.symbol == self._symbol
      and position.magic == self._magic
      and position.comment == self._comment
    ]

  def get_owned_position(self, ticket: int):
    if ticket <= 0:
      raise ValueError("Position ticket must be greater than 0")

    for position in self.get_owned_positions():
      if position.ticket == ticket:
        return position

    return None

  def close_position(self, ticket: int) -> None:
    position = self.get_owned_position(ticket)

    if position is None:
      raise RuntimeError(
        f"Position {ticket} is not owned by this executor"
      )

    tick = self._mt5.symbol_info_tick(self._symbol)

    if tick is None:
      raise RuntimeError(
        f"Cannot get current tick for {self._symbol}: "
        f"{self._mt5.last_error()}"
      )

    if position.type == self._mt5.POSITION_TYPE_BUY:
      price = tick.bid
    elif position.type == self._mt5.POSITION_TYPE_SELL:
      price = tick.ask
    else:
      raise RuntimeError(f"Unsupported position type: {position.type}")

    self.last_request = self._builder.build_close_request(
      position=position,
      price=price,
      magic=self._magic,
      comment=self._comment
    )

    if not self._live_trading:
      return

    self.last_result = self._mt5.order_send(self.last_request)

    if self.last_result is None:
      raise RuntimeError(
        f"MT5 close order failed: {self._mt5.last_error()}"
      )

    if self.last_result.retcode != self._mt5.TRADE_RETCODE_DONE:
      raise RuntimeError(
        f"MT5 close order rejected: retcode={self.last_result.retcode}"
      )

  def close_owned_positions(self) -> int:
    positions = self.get_owned_positions()

    for position in positions:
      self.close_position(position.ticket)

    return len(positions)
