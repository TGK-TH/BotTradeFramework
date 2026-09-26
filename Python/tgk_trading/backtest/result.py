from dataclasses import dataclass

from tgk_trading.backtest.trade_statistics import TradeStatistics
from tgk_trading.domain.trade import Trade


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
  trades: list[Trade]
  trade_statistics: TradeStatistics
