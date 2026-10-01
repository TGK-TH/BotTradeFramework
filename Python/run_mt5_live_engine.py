from tgk_trading.brokers.mt5 import MT5Adapter
from tgk_trading.live.engine import LiveEngine
from tgk_trading.live.order_executor import MT5OrderExecutor
from tgk_trading.strategies.cdc_account_3 import CDCAccount3Strategy
from tgk_trading.domain.timeframe import Timeframe

SYMBOL = "XAUUSD"
TIMEFRAME = Timeframe.M15
MAGIC = 4001
COMMENT = "TGK_PYTHON"
ORDER_QUANTITY = 0.01
CANDLE_COUNT = 100

def main() -> None:
  adapter = MT5Adapter()
  adapter.connect()

  try:
    executor = MT5OrderExecutor(
      adapter._mt5,
      SYMBOL,
      magic=MAGIC,
      comment=COMMENT,
      live_trading=False
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
    new_candles = engine.poll(count=CANDLE_COUNT)

    print("Warmup candles:", len(warmup_candles))

    print("MT5 connected:", adapter.is_connected())
    print("Mode: SAFE PREVIEW")
    print("New closed candles:", len(new_candles))

    if new_candles:
      print("Latest closed candle:", new_candles[-1].time)

    request = executor.get_last_request()
    if request is None:
      print("Signal: NONE")
      print("No order request was created.")
      return

    print("Signal produced an order request:")
    for key, value in request.items():
      print(f"  {key}: {value}")

    print("No order was sent.")
  finally:
    adapter.disconnect()
    print("MT5 disconnected:", not adapter.is_connected())

if __name__ == "__main__":
  main()
