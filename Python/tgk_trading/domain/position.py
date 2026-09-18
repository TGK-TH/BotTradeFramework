from dataclasses import dataclass
from enum import Enum

class PositionSide(Enum):
  BUY = "BUY"
  SELL = "SELL"

@dataclass(frozen=True)
class Position:
  side: PositionSide
  quantity: float
  entry_price: float
