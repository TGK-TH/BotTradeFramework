from datetime import datetime
from pathlib import Path

from tgk_trading.data.csv_loader import load_candles_from_csv


REFERENCE_CSV = Path(__file__).parent / "reference" / "tgk_ema_reference.csv"


def test_load_mt5_reference_csv():
  candles = load_candles_from_csv(REFERENCE_CSV)

  assert len(candles) == 1200

  assert candles[0].time == datetime(2026, 7, 10, 18, 0)
  assert candles[0].open == 4092.75
  assert candles[0].high == 4113.39
  assert candles[0].low == 4091.28
  assert candles[0].close == 4112.83

  assert candles[-1].time == datetime(2026, 9, 25, 8, 0)
  assert candles[-1].open == 4262.84
  assert candles[-1].high == 4275.70
  assert candles[-1].low == 4256.04
  assert candles[-1].close == 4266.63


def test_mt5_reference_candles_are_chronological():
  candles = load_candles_from_csv(REFERENCE_CSV)

  for previous, current in zip(candles, candles[1:]):
    assert current.time > previous.time
