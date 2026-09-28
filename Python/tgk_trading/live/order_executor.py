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
    price: float
  ) -> dict:
    if order.type != OrderType.MARKET:
      raise ValueError(f"Unsupported order type: {order.type}")

    if order.quantity <= 0:
      raise ValueError("Order quantity must be greater than 0")

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
      "type_time": self._mt5.ORDER_TIME_GTC,
      "type_filling": self._mt5.ORDER_FILLING_IOC
    }
