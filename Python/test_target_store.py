from datetime import datetime

from tgk_trading.domain.position import Position, PositionSide
from tgk_trading.domain.signal import Signal, SignalType
from tgk_trading.domain.timeframe import Timeframe
from tgk_trading.live.engine import LiveEngine
from tgk_trading.live.position_reconciler import PositionReconciler
from tgk_trading.live.target_store import JsonTargetPositionStore

class FakeStrategy:
  def on_candle(self, data):
    return Signal(SignalType.NONE)

class RecordingRestartExecutor:
  def __init__(self):
    self.events = []
    self.orders = []

  def get_owned_positions(self):
    return []

  def close_owned_positions(self):
    self.events.append("close")
    return 0

  def submit_order(self, order):
    self.events.append("submit")
    self.orders.append(order)

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


def test_live_engine_restores_target_and_reconciles_after_restart(tmp_path):
  path = tmp_path / "target.json"
  store = JsonTargetPositionStore(path)
  signal_bar_time = datetime(2026, 9, 28, 11, 15)

  first_reconciler = PositionReconciler(store)
  first_reconciler.set_target(SignalType.SELL, signal_bar_time)

  second_reconciler = PositionReconciler(store)

  class FakeAdapter:
    def get_candles(self, symbol, timeframe, count):
      return []

  executor = RecordingRestartExecutor()
  engine = LiveEngine(
    adapter=FakeAdapter(),
    symbol="XAUUSD",
    timeframe=Timeframe.M15,
    strategy=FakeStrategy(),
    order_executor=executor,
    position_reconciler=second_reconciler
  )

  engine.poll()

  assert executor.events == ["submit"]
  assert executor.orders[0].side.value == "SELL"
