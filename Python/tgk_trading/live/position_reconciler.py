from enum import Enum

from tgk_trading.domain.position import Position, PositionSide
from tgk_trading.domain.signal import SignalType
from tgk_trading.live.target_store import TargetPositionStore


class ReconciliationAction(Enum):
  NONE = "NONE"
  OPEN_BUY = "OPEN_BUY"
  OPEN_SELL = "OPEN_SELL"
  CLOSE_AND_OPEN_BUY = "CLOSE_AND_OPEN_BUY"
  CLOSE_AND_OPEN_SELL = "CLOSE_AND_OPEN_SELL"


class PositionReconciler:
  def __init__(self, store: TargetPositionStore | None = None):
    self._store = store
    self._target = None
    self._signal_bar_time = None
    if self._store is not None:
      self.restore()

  def set_target(
    self,
    signal_type: SignalType,
    signal_bar_time=None
  ) -> None:
    if signal_type == SignalType.BUY:
      self._target = PositionSide.BUY
    elif signal_type == SignalType.SELL:
      self._target = PositionSide.SELL
    else:
      return

    self._signal_bar_time = signal_bar_time
    if self._store is not None:
      self._store.save(self._target, self._signal_bar_time)

  def target(self) -> PositionSide | None:
    return self._target

  def restore(self) -> None:
    if self._store is None:
      return
    self._target, self._signal_bar_time = self._store.load()

  def signal_bar_time(self):
    return self._signal_bar_time

  def clear(self) -> None:
    self._target = None
    self._signal_bar_time = None
    if self._store is not None:
      self._store.clear()

  def reconcile(self, positions: list[Position]) -> ReconciliationAction:
    if self._target is None:
      return ReconciliationAction.NONE

    has_target = any(position.side == self._target for position in positions)
    if has_target:
      self.clear()
      return ReconciliationAction.NONE

    if any(position.side != self._target for position in positions):
      if self._target == PositionSide.BUY:
        return ReconciliationAction.CLOSE_AND_OPEN_BUY
      return ReconciliationAction.CLOSE_AND_OPEN_SELL

    if self._target == PositionSide.BUY:
      return ReconciliationAction.OPEN_BUY
    return ReconciliationAction.OPEN_SELL
