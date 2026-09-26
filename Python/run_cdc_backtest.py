from tgk_trading.backtest.engine import BacktestEngine
from tgk_trading.backtest.report import format_backtest_report
from tgk_trading.data.csv_loader import load_candles_from_csv
from tgk_trading.strategies.cdc_account_3 import CDCAccount3Strategy


REFERENCE_CSV = "Python/reference/tgk_ema_reference.csv"
INITIAL_BALANCE = 10000.0
WARMUP_BARS = 200


def main() -> None:
  candles = load_candles_from_csv(REFERENCE_CSV)
  strategy = CDCAccount3Strategy()
  engine = BacktestEngine(
    strategy=strategy,
    initial_balance=INITIAL_BALANCE
  )

  result = engine.run(candles, warmup_bars=WARMUP_BARS)

  print(f"Candles: {len(candles)}")
  print(format_backtest_report(result))


if __name__ == "__main__":
  main()
