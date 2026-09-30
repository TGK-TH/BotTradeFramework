import argparse

from tgk_trading.brokers.mt5 import MT5Adapter
from tgk_trading.domain.order import Order, OrderSide, OrderType
from tgk_trading.live.order_executor import MT5OrderExecutor


SYMBOL = "XAUUSD"
MAGIC = 4001
COMMENT = "TGK_PYTHON"
VOLUME = 0.01


def main() -> None:
  parser = argparse.ArgumentParser()
  parser.add_argument(
    "--live",
    action="store_true",
    help="Allow sending the demo order to MT5"
  )
  parser.add_argument(
    "--confirm",
    help="Exact confirmation text required for live mode"
  )
  args = parser.parse_args()

  confirmation = "BUY XAUUSD 0.01"
  live_trading = args.live and args.confirm == confirmation

  if args.live and not live_trading:
    raise SystemExit(
      f'Live mode requires: --confirm "{confirmation}"'
    )

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
    print("Mode:", "LIVE" if live_trading else "SAFE PREVIEW")

    executor = MT5OrderExecutor(
      mt5,
      SYMBOL,
      magic=MAGIC,
      comment=COMMENT,
      live_trading=live_trading
    )

    owned_before = {
      position.ticket
      for position in executor.get_owned_positions()
    }

    order = Order(
      type=OrderType.MARKET,
      side=OrderSide.BUY,
      quantity=VOLUME
    )

    executor.submit_order(order)
    request = executor.get_last_request()

    print("\nOrder request:")
    for key, value in request.items():
      print(f"  {key}: {value}")

    if not live_trading:
      print("\nNo order was sent.")
      print("This preview verifies the final request before any live action.")
      return

    result = executor.get_last_result()
    print("\nOrder sent successfully.")
    print("MT5 retcode:", result.retcode)

    owned_after = executor.get_owned_positions()
    new_positions = [
      position
      for position in owned_after
      if position.ticket not in owned_before
    ]

    if not new_positions:
      raise RuntimeError(
        "Order was accepted, but no new owned position was found."
      )

    print("\nNew owned position:")
    for position in new_positions:
      print(f"  ticket: {position.ticket}")
      print(f"  symbol: {position.symbol}")
      print(f"  magic: {position.magic}")
      print(f"  comment: {position.comment}")
      print(f"  type: {position.type}")
      print(f"  volume: {position.volume}")
      print(f"  price_open: {position.price_open}")
  finally:
    adapter.disconnect()
    print("\nMT5 disconnected:", not adapter.is_connected())


if __name__ == "__main__":
  main()
