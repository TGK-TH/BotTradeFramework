from dataclasses import dataclass


@dataclass(frozen=True)
class BacktestResult:
  initial_balance: float
  final_balance: float
  realized_pnl: float
  unrealized_pnl: float
  equity: float
  equity_curve: list[float]
  max_drawdown: float
  max_drawdown_percent: float
