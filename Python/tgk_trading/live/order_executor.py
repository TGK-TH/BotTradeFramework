from typing import Protocol

from tgk_trading.domain.order import Order


class OrderExecutor(Protocol):
  def submit_order(self, order: Order) -> None:
    ...


class RecordingOrderExecutor:
  def __init__(self):
    self.orders: list[Order] = []

  def submit_order(self, order: Order) -> None:
    self.orders.append(order)
