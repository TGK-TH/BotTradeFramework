from abc import ABC, abstractmethod

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.signal import Signal

class Strategy(ABC):

  @abstractmethod
  def on_candle(self, candle: Candle) -> Signal:
    pass
