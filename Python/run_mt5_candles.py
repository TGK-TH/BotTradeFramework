from tgk_trading.brokers.mt5 import MT5Adapter
from tgk_trading.domain.timeframe import Timeframe


def main() -> None:
  adapter = MT5Adapter()

  try:
    adapter.connect()

    candles = adapter.get_candles(
      symbol="XAUUSD",
      timeframe=Timeframe.M15,
      count=5
    )

    print(f"Candles: {len(candles)}")

    for candle in candles:
      print(
        f"{candle.time} "
        f"O={candle.open} "
        f"H={candle.high} "
        f"L={candle.low} "
        f"C={candle.close}"
      )
  finally:
    adapter.disconnect()


if __name__ == "__main__":
  main()
