def calculate_drawdown_curve(
  equity_curve: list[float]
) -> list[float]:
  if not equity_curve:
    return []

  peak = equity_curve[0]
  drawdown_curve = []

  for equity in equity_curve:
    if equity > peak:
      peak = equity

    drawdown = peak - equity
    drawdown_curve.append(drawdown)

  return drawdown_curve


def calculate_max_drawdown(
  equity_curve: list[float]
) -> float:
  drawdown_curve = calculate_drawdown_curve(equity_curve)

  if not drawdown_curve:
    return 0.0

  return max(drawdown_curve)
