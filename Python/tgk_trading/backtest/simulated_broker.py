from tgk_trading.domain.order import Order, OrderSide, OrderType
from tgk_trading.domain.position import Position, PositionSide
from tgk_trading.domain.position_lifecycle import (
  ClosedPosition,
  PositionLifecycle
)


class SimulatedBroker:

  def execute_order(
    self,
    order: Order,
    price: float
  ) -> Position:

    if order.type != OrderType.MARKET:
      raise ValueError(
        f"Unsupported order type: {order.type}"
      )

    if order.side == OrderSide.BUY:
      position_side = PositionSide.BUY
    elif order.side == OrderSide.SELL:
      position_side = PositionSide.SELL
    else:
      raise ValueError(
        f"Unsupported order side: {order.side}"
      )

    return Position(
      side=position_side,
      quantity=order.quantity,
      entry_price=price
    )

  def close_position(
    self,
    position: Position,
    price: float
  ) -> ClosedPosition:

    return PositionLifecycle.close(
      position=position,
      exit_price=price
    )
