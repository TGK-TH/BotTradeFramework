from enum import Enum

from tgk_trading.domain.position import Position, PositionSide
from tgk_trading.domain.signal import SignalType


class ReconciliationAction(Enum):
  NONE = "NONE"
  OPEN_BUY = "OPEN_BUY"
  OPEN_SELL = "OPEN_SELL"
  CLOSE_AND_OPEN_BUY = "CLOSE_AND_OPEN_BUY"
  CLOSE_AND_OPEN_SELL = "CLOSE_AND_OPEN_SELL"


class PositionReconciler:
  def __init__(self):
    self._target = None

  def set_target(self, signal_type: SignalType) -> None:
    if signal_type == SignalType.BUY:
      self._target = PositionSide.BUY
    elif signal_type == SignalType.SELL:
      self._target = PositionSide.SELL

  def target(self) -> PositionSide | None:
    return self._target

  def reconcile(self, positions: list[Position]) -> ReconciliationAction:
    if self._target is None:
      return ReconciliationAction.NONE

    has_target = any(position.side == self._target for position in positions)
    if has_target:
      self._target = None
      return ReconciliationAction.NONE

    if any(position.side != self._target for position in positions):
      if self._target == PositionSide.BUY:
        return ReconciliationAction.CLOSE_AND_OPEN_BUY
      return ReconciliationAction.CLOSE_AND_OPEN_SELL

    if self._target == PositionSide.BUY:
      return ReconciliationAction.OPEN_BUY
    return ReconciliationAction.OPEN_SELL
