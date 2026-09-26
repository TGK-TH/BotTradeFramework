from dataclasses import dataclass
from datetime import datetime

from tgk_trading.domain.position import PositionSide


@dataclass(frozen=True)
class Trade:
  side: PositionSide
  quantity: float
  entry_time: datetime
  entry_price: float
  exit_time: datetime
  exit_price: float
  pnl: float
