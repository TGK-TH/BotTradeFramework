from datetime import datetime
from pathlib import Path

from tgk_trading.data.csv_loader import load_candles_from_csv


def test_load_candles_from_csv(tmp_path: Path):
  csv_path = tmp_path / "candles.csv"
  csv_path.write_text(
    "time,open,high,low,close\n"
    "2026.09.01 10:00,4500.0,4510.0,4490.0,4505.0\n"
    "2026.09.01 10:15,4505.0,4520.0,4500.0,4515.0\n",
    encoding="utf-8"
  )

  candles = load_candles_from_csv(csv_path)

  assert len(candles) == 2
  assert candles[0].time == datetime(2026, 9, 1, 10, 0)
  assert candles[0].open == 4500.0
  assert candles[0].high == 4510.0
  assert candles[0].low == 4490.0
  assert candles[0].close == 4505.0
  assert candles[1].time == datetime(2026, 9, 1, 10, 15)
  assert candles[1].close == 4515.0


def test_load_candles_requires_ohlc_columns(tmp_path: Path):
  csv_path = tmp_path / "invalid.csv"
  csv_path.write_text(
    "time,close\n"
    "2026.09.01 10:00,4505.0\n",
    encoding="utf-8"
  )

  try:
    load_candles_from_csv(csv_path)
    assert False, "Expected ValueError"
  except ValueError as error:
    assert str(error) == (
      "CSV must contain columns: time, open, high, low, close"
    )
