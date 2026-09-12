from tgk_trading.domain.candle import Candle
from tgk_trading.domain.signal import Signal, SignalType
from tgk_trading.strategies.base import Strategy

class SimpleStrategy(Strategy):

  def on_candle(self, candle: Candle) -> Signal:
    if candle.close > candle.open:
      return Signal(SignalType.BUY)

    if candle.close < candle.open:
      return Signal(SignalType.SELL)

    return Signal(SignalType.NONE)
