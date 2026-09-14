from dataclasses import dataclass
from enum import Enum

class SignalType(Enum):
  NONE = "NONE"
  BUY = "BUY"
  SELL = "SELL"

@dataclass(frozen=True)
class Signal:
  type: SignalType
