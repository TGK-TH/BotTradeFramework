from datetime import datetime, timezone

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.timeframe import Timeframe


class MT5Adapter:
  def __init__(self, mt5_module=None):
    self._mt5 = mt5_module
    self._connected = False

  def connect(self) -> None:
    if self._connected:
      return

    if self._mt5 is None:
      try:
        import MetaTrader5 as mt5
      except ImportError as error:
        raise RuntimeError(
          "MetaTrader5 package is not available in this Python runtime"
        ) from error
      self._mt5 = mt5

    if not self._mt5.initialize():
      raise RuntimeError(
        f"MT5 initialize failed: {self._mt5.last_error()}"
      )

    self._connected = True

  def disconnect(self) -> None:
    if not self._connected:
      return

    self._mt5.shutdown()
    self._connected = False

  def is_connected(self) -> bool:
    return self._connected

  def get_candles(
    self,
    symbol: str,
    timeframe: Timeframe,
    count: int
  ) -> list[Candle]:
    if not self._connected:
      raise RuntimeError("MT5 is not connected")

    if count <= 0:
      raise ValueError("count must be greater than 0")

    mt5_timeframe = getattr(
      self._mt5,
      f"TIMEFRAME_{timeframe.value}"
    )

    rates = self._mt5.copy_rates_from_pos(
      symbol,
      mt5_timeframe,
      1,
      count
    )

    if rates is None:
      raise RuntimeError(
        f"MT5 failed to get candles: {self._mt5.last_error()}"
      )

    candles: list[Candle] = []

    for rate in rates:
      time = datetime.fromtimestamp(
        int(rate["time"]),
        tz=timezone.utc
      ).replace(tzinfo=None)

      candles.append(Candle(
        time=time,
        open=float(rate["open"]),
        high=float(rate["high"]),
        low=float(rate["low"]),
        close=float(rate["close"])
      ))

    return candles
