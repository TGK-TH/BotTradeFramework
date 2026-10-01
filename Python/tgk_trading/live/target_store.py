import json
from datetime import datetime
from pathlib import Path
from typing import Protocol

from tgk_trading.domain.position import PositionSide

class TargetPositionStore(Protocol):
  def save(
    self,
    target: PositionSide,
    signal_bar_time: datetime | None
  ) -> None:
    ...

  def load(self) -> tuple[PositionSide | None, datetime | None]:
    ...

  def clear(self) -> None:
    ...

class JsonTargetPositionStore:
  def __init__(self, path: str | Path):
    self._path = Path(path)

  def save(
    self,
    target: PositionSide,
    signal_bar_time: datetime | None
  ) -> None:
    self._path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
      "target": target.value,
      "signal_bar_time": (
        signal_bar_time.isoformat()
        if signal_bar_time is not None
        else None
      )
    }
    self._path.write_text(
      json.dumps(payload),
      encoding="utf-8"
    )

  def load(self) -> tuple[PositionSide | None, datetime | None]:
    if not self._path.exists():
      return None, None

    payload = json.loads(
      self._path.read_text(encoding="utf-8")
    )

    target_value = payload.get("target")
    signal_bar_value = payload.get("signal_bar_time")

    target = (
      PositionSide(target_value)
      if target_value is not None
      else None
    )
    signal_bar_time = (
      datetime.fromisoformat(signal_bar_value)
      if signal_bar_value is not None
      else None
    )

    return target, signal_bar_time

  def clear(self) -> None:
    if self._path.exists():
      self._path.unlink()
