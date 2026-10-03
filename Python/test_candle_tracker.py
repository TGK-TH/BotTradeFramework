from datetime import datetime

from tgk_trading.domain.candle import Candle
from tgk_trading.live.candle_tracker import ClosedCandleTracker


def candle(hour: int) -> Candle:
  return Candle(
    time=datetime(2026, 9, 25, hour),
    open=100.0,
    high=101.0,
    low=99.0,
    close=100.5
  )


def test_tracker_returns_all_candles_on_first_poll():
  tracker = ClosedCandleTracker()

  result = tracker.new_candles([
    candle(9),
    candle(10),
    candle(11)
  ])

  assert [item.time for item in result] == [
    datetime(2026, 9, 25, 9),
    datetime(2026, 9, 25, 10),
    datetime(2026, 9, 25, 11)
  ]
  assert tracker.last_processed_time() == datetime(2026, 9, 25, 11)


def test_tracker_ignores_already_processed_candles():
  tracker = ClosedCandleTracker()

  tracker.new_candles([
    candle(9),
    candle(10),
    candle(11)
  ])

  result = tracker.new_candles([
    candle(10),
    candle(11)
  ])

  assert result == []


def test_tracker_returns_only_new_candles():
  tracker = ClosedCandleTracker()

  tracker.new_candles([
    candle(9),
    candle(10)
  ])

  result = tracker.new_candles([
    candle(10),
    candle(11),
    candle(12)
  ])

  assert [item.time for item in result] == [
    datetime(2026, 9, 25, 11),
    datetime(2026, 9, 25, 12)
  ]


def test_tracker_handles_multiple_new_candles_after_missed_poll():
  tracker = ClosedCandleTracker()

  tracker.new_candles([
    candle(9)
  ])

  result = tracker.new_candles([
    candle(10),
    candle(11),
    candle(12)
  ])

  assert [item.time for item in result] == [
    datetime(2026, 9, 25, 10),
    datetime(2026, 9, 25, 11),
    datetime(2026, 9, 25, 12)
  ]
