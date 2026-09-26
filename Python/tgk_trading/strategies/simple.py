from tgk_trading.domain.market_data import CandleSeries
from tgk_trading.domain.signal import Signal, SignalType
from tgk_trading.strategies.base import Strategy

class SimpleStrategy(Strategy):

  def on_candle(self, data: CandleSeries) -> Signal:
    candle = data.current()

    if candle is None:
      return Signal(SignalType.NONE)

    if candle.close > candle.open:
      return Signal(SignalType.BUY)

    if candle.close < candle.open:
      return Signal(SignalType.SELL)

    return Signal(SignalType.NONE)
