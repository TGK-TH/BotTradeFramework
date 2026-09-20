from dataclasses import dataclass

from tgk_trading.domain.pnl import calculate_pnl
from tgk_trading.domain.position import Position

@dataclass(frozen=True)
class ClosedPosition:
  position: Position
  exit_price: float
  pnl: float

class PositionLifecycle:

  @staticmethod
  def close(
    position: Position,
    exit_price: float,
  ) -> ClosedPosition:

    pnl = calculate_pnl(
      side=position.side,
      entry_price=position.entry_price,
      exit_price=exit_price,
      quantity=position.quantity,
    )

    return ClosedPosition(
      position=position,
      exit_price=exit_price,
      pnl=pnl,
    )
