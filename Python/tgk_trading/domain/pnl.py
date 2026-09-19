from tgk_trading.domain.position import PositionSide

def calculate_pnl(
  side: PositionSide,
  entry_price: float,
  exit_price: float,
  quantity: float,
) -> float:
  if side == PositionSide.BUY:
    return (exit_price - entry_price) * quantity

  if side == PositionSide.SELL:
    return (entry_price - exit_price) * quantity

  return ValueError(f"Unsupported position side: {side}")
