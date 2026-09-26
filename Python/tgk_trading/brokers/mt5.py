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
