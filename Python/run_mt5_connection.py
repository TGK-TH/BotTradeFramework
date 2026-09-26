from tgk_trading.brokers.mt5 import MT5Adapter


def main() -> None:
  adapter = MT5Adapter()

  try:
    adapter.connect()
    print("MT5 connected:", adapter.is_connected())
  finally:
    adapter.disconnect()
    print("MT5 disconnected:", not adapter.is_connected())


if __name__ == "__main__":
  main()
