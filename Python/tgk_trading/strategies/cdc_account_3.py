from tgk_trading.domain.market_data import CandleSeries
from tgk_trading.domain.signal import Signal, SignalType
from tgk_trading.indicators.ema import EMA
from tgk_trading.strategies.base import Strategy

class CDCAccount3Strategy(Strategy):

  def __init__(self):
    self._fast_ema = EMA(12)
    self._slow_ema = EMA(26)

  def on_candle(self, data: CandleSeries) -> Signal:
    fast_current = self._fast_ema.calculate(data, shift=0)
    fast_previous = self._fast_ema.calculate(data, shift=1)

    slow_current = self._slow_ema.calculate(data, shift=0)
    slow_previous = self._slow_ema.calculate(data, shift=1)

    if (
      fast_current is None
      or fast_previous is None
      or slow_current is None
      or slow_previous is None
    ):
      return Signal(SignalType.NONE)

    if fast_previous <= slow_previous and fast_current > slow_current:
      return Signal(SignalType.BUY)

    if fast_previous >= slow_previous and fast_current < slow_current:
      return Signal(SignalType.SELL)

    return Signal(SignalType.NONE)
