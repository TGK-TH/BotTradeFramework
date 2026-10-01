import argparse
import time

from tgk_trading.brokers.mt5 import MT5Adapter
from tgk_trading.domain.timeframe import Timeframe
from tgk_trading.live.engine import LiveEngine
from tgk_trading.live.order_executor import MT5OrderExecutor
from tgk_trading.strategies.cdc_account_3 import CDCAccount3Strategy

SYMBOL = "XAUUSD"
TIMEFRAME = Timeframe.M15
MAGIC = 4001
COMMENT = "TGK_PYTHON"
ORDER_QUANTITY = 0.01
CANDLE_COUNT = 100
POLL_SECONDS = 5


def main() -> None:
  parser = argparse.ArgumentParser()
  parser.add_argument(
    "--once",
    action="store_true",
    help="Run one poll cycle and exit"
  )
  parser.add_argument(
    "--live",
    action="store_true",
    help="Enable real MT5 order sending"
  )
  parser.add_argument(
    "--confirm",
    default="",
    help="Required confirmation for live trading"
  )
  args = parser.parse_args()

  expected_confirmation = (
    f"LIVE {SYMBOL} {TIMEFRAME.value} {ORDER_QUANTITY}"
  )

  if args.live and args.confirm != expected_confirmation:
    raise SystemExit(
      f'Live trading requires --confirm "{expected_confirmation}"'
    )

  adapter = MT5Adapter()
  adapter.connect()

  try:
    executor = MT5OrderExecutor(
      adapter._mt5,
      SYMBOL,
      magic=MAGIC,
      comment=COMMENT,
      live_trading=args.live
    )
    engine = LiveEngine(
      adapter=adapter,
      symbol=SYMBOL,
      timeframe=TIMEFRAME,
      strategy=CDCAccount3Strategy(),
      order_executor=executor,
      order_quantity=ORDER_QUANTITY
    )

    warmup_candles = engine.warmup(count=CANDLE_COUNT)
    print("Warmup candles:", len(warmup_candles))
    print("MT5 connected:", adapter.is_connected())
    print("Mode:", "LIVE" if args.live else "SAFE PREVIEW")

    positions = engine.positions()
    print("Owned positions:", len(positions))
    for position in positions:
      print(
        f"  {position.side.value} "
        f"volume={position.quantity} "
        f"entry={position.entry_price}"
      )

    while True:
      new_candles = engine.poll(count=CANDLE_COUNT)
      print("New closed candles:", len(new_candles))

      if new_candles:
        print("Latest closed candle:", new_candles[-1].time)

      request = executor.get_last_request()
      if request is not None:
        print("Signal produced an order request:")
        for key, value in request.items():
          print(f"  {key}: {value}")
        if not args.live:
          print("No order was sent.")

      if args.once:
        break

      time.sleep(POLL_SECONDS)
  except KeyboardInterrupt:
    print("Stopping live engine.")
  finally:
    adapter.disconnect()
    print("MT5 disconnected:", not adapter.is_connected())


if __name__ == "__main__":
  main()
