from dataclasses import dataclass

from tgk_trading.domain.position import Position


@dataclass(frozen=True)
class Trade:
  position: Position
  exit_price: float
  pnl: float
