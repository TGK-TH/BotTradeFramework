from tgk_trading.domain.position import Position

class Account:

  def __init__(self, balance: float):
    self._balance = balance
    self._positions: list[Position] = []

  def balance(self) -> float:
    return self._balance

  def positions(self) -> list[Position]:
    return list(self._positions)

  def add_position(self, position: Position):
    self._positions.append(position)

  def remove_position(self, position: Position):
    self._positions.remove(position)

  def apply_realized_pnl(self, pnl: float):
    self._balance += pnl
