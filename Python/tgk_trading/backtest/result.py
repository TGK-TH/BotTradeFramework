from dataclasses import dataclass


@dataclass(frozen=True)
class BacktestResult:
  initial_balance: float
  final_balance: float
  realized_pnl: float
