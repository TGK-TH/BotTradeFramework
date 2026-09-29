from tgk_trading.brokers.mt5 import MT5Adapter


def main() -> None:
  adapter = MT5Adapter()

  try:
    adapter.connect()
    print("MT5 connected:", adapter.is_connected())

    account = adapter._mt5.account_info()
    if account is None:
      raise RuntimeError(
        f"MT5 account_info failed: {adapter._mt5.last_error()}"
      )

    print("Account login:", account.login)
    print("Account server:", account.server)
    print("Account balance:", account.balance)
    print("Account equity:", account.equity)

    tick = adapter._mt5.symbol_info_tick("XAUUSD")
    if tick is None:
      raise RuntimeError(
        f"XAUUSD tick failed: {adapter._mt5.last_error()}"
      )

    print("XAUUSD bid:", tick.bid)
    print("XAUUSD ask:", tick.ask)
  finally:
    adapter.disconnect()
    print("MT5 disconnected:", not adapter.is_connected())


if __name__ == "__main__":
  main()
