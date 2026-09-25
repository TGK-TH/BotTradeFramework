from datetime import datetime
from pathlib import Path

from tgk_trading.data.csv_loader import load_candles_from_csv


REFERENCE_CSV = Path(__file__).parent / "reference" / "tgk_ema_reference.csv"


def test_load_mt5_reference_csv():
  candles = load_candles_from_csv(REFERENCE_CSV)

  assert len(candles) == 1000

  assert candles[0].time == datetime(2026, 7, 23, 17, 0)
  assert candles[0].open == 4043.24
  assert candles[0].high == 4061.66
  assert candles[0].low == 4040.11
  assert candles[0].close == 4057.83

  assert candles[-1].time == datetime(2026, 9, 25, 5, 0)
  assert candles[-1].open == 4287.83
  assert candles[-1].high == 4295.17
  assert candles[-1].low == 4277.42
  assert candles[-1].close == 4283.61


def test_mt5_reference_candles_are_chronological():
  candles = load_candles_from_csv(REFERENCE_CSV)

  for previous, current in zip(candles, candles[1:]):
    assert current.time > previous.time
