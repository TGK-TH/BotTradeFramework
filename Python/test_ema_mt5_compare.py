from datetime import datetime
from pathlib import Path
import sys

import pandas as pd

from tgk_trading.domain.candle import Candle
from tgk_trading.domain.market_data import CandleSeries
from tgk_trading.indicators.ema import EMA


DEFAULT_REFERENCE_FILE = Path(__file__).resolve().parent / "reference" / "tgk_ema_reference.csv"
FAST_EMA = 12
SLOW_EMA = 26
WARMUP_BARS = 100


def load_reference(path: Path) -> pd.DataFrame:
  df = pd.read_csv(path)
  required_columns = {"time", "close", "ema12", "ema26"}

  missing = required_columns - set(df.columns)
  if missing:
    raise ValueError(f"Missing columns: {sorted(missing)}")

  df["time"] = pd.to_datetime(df["time"])
  df["close"] = pd.to_numeric(df["close"])
  df["ema12"] = pd.to_numeric(df["ema12"])
  df["ema26"] = pd.to_numeric(df["ema26"])

  return df


def calculate_python_ema(df: pd.DataFrame, period: int) -> list[float | None]:
  series = CandleSeries()
  indicator = EMA(period)
  values = []

  for row in df.itertuples(index=False):
    series.append(
      Candle(
        time=row.time.to_pydatetime() if hasattr(row.time, "to_pydatetime") else row.time,
        open=row.close,
        high=row.close,
        low=row.close,
        close=row.close,
      )
    )
    values.append(indicator.calculate(series))

  return values


def compare_column(
  name: str,
  python_values: list[float | None],
  mt5_values: pd.Series,
) -> None:
  differences = []

  for python_value, mt5_value in zip(python_values, mt5_values):
    if python_value is None or pd.isna(mt5_value):
      continue

    differences.append(abs(python_value - mt5_value))

  if not differences:
    print(f"{name}: no comparable values")
    return

  warmup_differences = differences[WARMUP_BARS:]
  if not warmup_differences:
    warmup_differences = differences

  print(f"{name}:")
  print(f"  Max difference (all):    {max(differences):.12f}")
  print(f"  Max difference (after {WARMUP_BARS} warmup): {max(warmup_differences):.12f}")
  print(f"  Mean difference (after {WARMUP_BARS} warmup): {sum(warmup_differences) / len(warmup_differences):.12f}")


def main() -> None:
  reference_file = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_REFERENCE_FILE

  if not reference_file.exists():
    raise FileNotFoundError(
      f"Reference file not found: {reference_file}\n"
      "Export it from MT5 first, then copy it to Python/reference/."
    )

  df = load_reference(reference_file)

  print(f"Reference file: {reference_file}")
  print(f"Bars: {len(df)}")
  print(f"From: {df.iloc[0]['time']}")
  print(f"To:   {df.iloc[-1]['time']}")
  print()

  python_ema12 = calculate_python_ema(df, FAST_EMA)
  python_ema26 = calculate_python_ema(df, SLOW_EMA)

  compare_column("EMA12", python_ema12, df["ema12"])
  compare_column("EMA26", python_ema26, df["ema26"])


if __name__ == "__main__":
  main()
