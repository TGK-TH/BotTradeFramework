from tgk_trading.brokers.mt5 import MT5Adapter
from tgk_trading.domain.order import Order, OrderSide, OrderType
from tgk_trading.live.order_executor import MT5OrderExecutor


SYMBOL = "XAUUSD"
MAGIC = 4001
COMMENT = "TGK_PYTHON"
VOLUME = 0.01


def main() -> None:
  adapter = MT5Adapter()

  try:
    adapter.connect()
    mt5 = adapter._mt5
    account = mt5.account_info()

    if account is None:
      raise RuntimeError(
        f"MT5 account_info failed: {mt5.last_error()}"
      )

    print("MT5 connected:", adapter.is_connected())
    print("Account server:", account.server)
    print("Trade allowed:", account.trade_allowed)
    print("Mode: SAFE PREVIEW")

    executor = MT5OrderExecutor(
      mt5,
      SYMBOL,
      magic=MAGIC,
      comment=COMMENT,
      live_trading=False
    )

    order = Order(
      type=OrderType.MARKET,
      side=OrderSide.BUY,
      quantity=VOLUME
    )

    executor.submit_order(order)
    request = executor.get_last_request()

    print("\nOrder request that would be sent:")
    for key, value in request.items():
      print(f"  {key}: {value}")

    print("\nNo order was sent.")
    print("This preview verifies the final request before any live action.")
  finally:
    adapter.disconnect()
    print("\nMT5 disconnected:", not adapter.is_connected())


if __name__ == "__main__":
  main()
