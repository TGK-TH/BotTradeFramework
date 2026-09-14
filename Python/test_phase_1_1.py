from datetime import datetime

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.signal import SignalType
from tgk_trading.strategies.simple import SimpleStrategy
from tgk_trading.strategies.base import Strategy

candle = Candle(
  time=datetime(2026, 9, 12, 10, 0),
  open=2500,
  high=2510,
  low=2495,
  close=2505,
)

strategy = SimpleStrategy()

signal = strategy.on_candle(candle)

print(f"Candle: {candle}")
print(f"Signal: {signal.type}")
