import csv
from datetime import datetime
from pathlib import Path

from tgk_trading.domain.candle import Candle


def load_candles_from_csv(path: str | Path) -> list[Candle]:
  candles: list[Candle] = []

  with open(path, newline="", encoding="utf-8") as file:
    reader = csv.DictReader(file)

    required_columns = {
      "time",
      "open",
      "high",
      "low",
      "close"
    }

    if not required_columns.issubset(reader.fieldnames or set()):
      raise ValueError(
        "CSV must contain columns: "
        "time, open, high, low, close"
      )

    for row in reader:
      candles.append(Candle(
        time=datetime.strptime(
          row["time"],
          "%Y.%m.%d %H:%M"
        ),
        open=float(row["open"]),
        high=float(row["high"]),
        low=float(row["low"]),
        close=float(row["close"])
      ))

  return candles
