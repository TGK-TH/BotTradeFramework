from abc import ABC, abstractmethod

from tgk_trading.domain.market_data import CandleSeries
from tgk_trading.domain.signal import Signal

class Strategy(ABC):

  @abstractmethod
  def on_candle(self, data: CandleSeries) -> Signal:
    pass
