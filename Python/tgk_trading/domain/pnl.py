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


def calculate_unrealized_pnl(
  side: PositionSide,
  entry_price: float,
  current_price: float,
  quantity: float
) -> float:

  if side == PositionSide.BUY:
    return (current_price - entry_price) * quantity

  if side == PositionSide.SELL:
    return (entry_price - current_price) * quantity

  raise ValueError(f"Unsupported position side: {side}")
