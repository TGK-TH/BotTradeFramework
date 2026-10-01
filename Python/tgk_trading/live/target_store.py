import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Protocol

from tgk_trading.domain.position import PositionSide

@dataclass(frozen=True)
class TargetPositionIdentity:
  symbol: str
  magic: int
  strategy_id: str

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
  def __init__(
    self,
    path: str | Path,
    identity: TargetPositionIdentity
  ):
    self._path = Path(path)
    self._identity = identity

  def save(
    self,
    target: PositionSide,
    signal_bar_time: datetime | None
  ) -> None:
    self._path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
      "symbol": self._identity.symbol,
      "magic": self._identity.magic,
      "strategy_id": self._identity.strategy_id,
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

    stored_identity = TargetPositionIdentity(
      symbol=payload.get("symbol"),
      magic=payload.get("magic"),
      strategy_id=payload.get("strategy_id")
    )

    if stored_identity != self._identity:
      raise RuntimeError(
        "Target position identity mismatch: "
        f"stored={stored_identity}, "
        f"current={self._identity}"
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
