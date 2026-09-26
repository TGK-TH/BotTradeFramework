from tgk_trading.brokers.mt5 import MT5Adapter


def main() -> None:
  adapter = MT5Adapter()

  try:
    adapter.connect()

    import MetaTrader5 as mt5

    candles = adapter.get_candles(
      symbol="XAUUSD",
      timeframe=mt5.TIMEFRAME_M15,
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
