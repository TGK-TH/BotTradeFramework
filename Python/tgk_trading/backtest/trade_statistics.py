from dataclasses import dataclass

from tgk_trading.domain.trade import Trade


@dataclass(frozen=True)
class TradeStatistics:
  total_trades: int
  winning_trades: int
  losing_trades: int
  win_rate: float
  gross_profit: float
  gross_loss: float
  profit_factor: float
  average_trade: float


def calculate_trade_statistics(
  trades: list[Trade]
) -> TradeStatistics:
  total_trades = len(trades)
  winning_trades = sum(1 for trade in trades if trade.pnl > 0)
  losing_trades = sum(1 for trade in trades if trade.pnl < 0)

  if total_trades == 0:
    win_rate = 0.0
  else:
    win_rate = (winning_trades / total_trades) * 100.0

  gross_profit = sum(
    trade.pnl for trade in trades if trade.pnl > 0
  )

  gross_loss = sum(
    -trade.pnl for trade in trades if trade.pnl < 0
  )

  if gross_loss == 0:
    if gross_profit > 0:
      profit_factor = float("inf")
    else:
      profit_factor = 0.0
  else:
    profit_factor = gross_profit / gross_loss

  if total_trades == 0:
    average_trade = 0.0
  else:
    average_trade = sum(trade.pnl for trade in trades) / total_trades

  return TradeStatistics(
    total_trades=total_trades,
    winning_trades=winning_trades,
    losing_trades=losing_trades,
    win_rate=win_rate,
    gross_profit=gross_profit,
    gross_loss=gross_loss,
    profit_factor=profit_factor,
    average_trade=average_trade
  )
