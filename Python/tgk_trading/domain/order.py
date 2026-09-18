from dataclasses import dataclass
from enum import Enum

class OrderType(Enum):
  MARKET = "MARKET"

class OrderSide(Enum):
  BUY = "BUY"
  SELL = "SELL"

@dataclass(frozen=True)
class Order:
  type: OrderType
  side: OrderSide
  quantity: float
