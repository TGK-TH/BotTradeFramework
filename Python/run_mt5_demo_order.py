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
  parser.add_argument(
    "--close-ticket",
    type=int,
    help="Close one owned position by ticket"
  )
  args = parser.parse_args()

  confirmation = "BUY XAUUSD 0.01"
  close_confirmation = f"CLOSE XAUUSD {args.close_ticket}"
  live_trading = args.confirm == confirmation or args.confirm == close_confirmation

  if args.close_ticket is not None and args.close_ticket <= 0:
    raise SystemExit("--close-ticket must be greater than 0")

  if args.close_ticket is not None:
    if args.confirm != close_confirmation:
      raise SystemExit(
        f'Close mode requires: --confirm "{close_confirmation}"'
      )
  elif args.live and args.confirm != confirmation:
    raise SystemExit(
      f'Live mode requires: --confirm "{confirmation}"'
    )
  elif not args.live:
    live_trading = False

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

    if args.close_ticket is not None:
      position = executor.get_owned_position(args.close_ticket)

      if position is None:
        raise RuntimeError(
          f"Position {args.close_ticket} is not owned by this executor"
        )

      print("\nPosition to close:")
      print(f"  ticket: {position.ticket}")
      print(f"  symbol: {position.symbol}")
      print(f"  magic: {position.magic}")
      print(f"  comment: {position.comment}")
      print(f"  type: {position.type}")
      print(f"  volume: {position.volume}")
      print(f"  price_open: {position.price_open}")

      executor.close_position(args.close_ticket)
      request = executor.get_last_request()

      print("\nClose request:")
      for key, value in request.items():
        print(f"  {key}: {value}")

      result = executor.get_last_result()
      print("\nPosition close sent successfully.")
      print("MT5 retcode:", result.retcode)

      remaining = executor.get_owned_position(args.close_ticket)
      if remaining is not None:
        raise RuntimeError(
          f"Position {args.close_ticket} is still open after close request"
        )

      print("Position closed and no longer owned by this executor.")
      return

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
