from dataclasses import dataclass
from datetime import datetime

from tgk_trading.domain.position import Position


@dataclass(frozen=True)
class Trade:
  position: Position
  entry_time: datetime
  exit_time: datetime
  exit_price: float
  pnl: float
