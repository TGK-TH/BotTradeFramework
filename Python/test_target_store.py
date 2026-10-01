from datetime import datetime

from tgk_trading.domain.position import Position, PositionSide
from tgk_trading.domain.signal import SignalType
from tgk_trading.live.position_reconciler import PositionReconciler
from tgk_trading.live.target_store import JsonTargetPositionStore

def test_json_target_store_round_trip(tmp_path):
  path = tmp_path / "target.json"
  store = JsonTargetPositionStore(path)
  signal_bar_time = datetime(2026, 9, 28, 10, 15)

  store.save(PositionSide.BUY, signal_bar_time)

  target, restored_time = store.load()

  assert target == PositionSide.BUY
  assert restored_time == signal_bar_time

def test_json_target_store_clear(tmp_path):
  path = tmp_path / "target.json"
  store = JsonTargetPositionStore(path)

  store.save(PositionSide.SELL, datetime(2026, 9, 28, 10, 30))
  store.clear()

  assert store.load() == (None, None)

def test_position_reconciler_restores_target_after_restart(tmp_path):
  path = tmp_path / "target.json"
  store = JsonTargetPositionStore(path)
  signal_bar_time = datetime(2026, 9, 28, 10, 45)

  first = PositionReconciler(store)
  first.set_target(
    signal_type=SignalType.SELL,
    signal_bar_time=signal_bar_time
  )

  second = PositionReconciler(store)

  assert second.target() == PositionSide.SELL
  assert second.signal_bar_time() == signal_bar_time

def test_position_reconciler_clears_persisted_target_when_position_exists(tmp_path):
  path = tmp_path / "target.json"
  store = JsonTargetPositionStore(path)
  reconciler = PositionReconciler(store)
  reconciler.set_target(
    SignalType.BUY,
    datetime(2026, 9, 28, 11, 0)
  )

  reconciler.reconcile([
    Position(
      side=PositionSide.BUY,
      quantity=0.01,
      entry_price=4050.25
    )
  ])

  assert reconciler.target() is None
  assert store.load() == (None, None)
