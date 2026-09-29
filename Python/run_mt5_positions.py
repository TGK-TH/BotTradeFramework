from tgk_trading.brokers.mt5 import MT5Adapter


MARGIN_MODE_NAMES = {
  0: "RETAIL_NETTING",
  1: "EXCHANGE",
  2: "RETAIL_HEDGING",
}


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

    margin_mode = int(account.margin_mode)
    print("MT5 connected:", adapter.is_connected())
    print("Account server:", account.server)
    print("Margin mode:", margin_mode, MARGIN_MODE_NAMES.get(margin_mode, "UNKNOWN"))
    print("Trade allowed:", account.trade_allowed)
    print("XAUUSD open positions:")

    positions = mt5.positions_get(symbol="XAUUSD")

    if positions is None:
      raise RuntimeError(
        f"MT5 positions_get failed: {mt5.last_error()}"
      )

    if len(positions) == 0:
      print("  none")
      return

    for position in positions:
      position_type = "BUY" if position.type == mt5.POSITION_TYPE_BUY else "SELL"
      print(
        "  ticket={ticket} magic={magic} type={type} volume={volume} "
        "symbol={symbol} price={price} comment={comment!r} profit={profit}".format(
          ticket=position.ticket,
          magic=position.magic,
          type=position_type,
          volume=position.volume,
          symbol=position.symbol,
          price=position.price_open,
          comment=position.comment,
          profit=position.profit,
        )
      )
  finally:
    adapter.disconnect()
    print("MT5 disconnected:", not adapter.is_connected())


if __name__ == "__main__":
  main()
