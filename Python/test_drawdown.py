from tgk_trading.backtest.drawdown import (
  calculate_drawdown_curve,
  calculate_max_drawdown
)


def test_drawdown_curve():
  equity_curve = [
    10000.0,
    10100.0,
    10050.0,
    9900.0,
    10020.0
  ]

  drawdown_curve = calculate_drawdown_curve(equity_curve)

  assert drawdown_curve == [
    0.0,
    0.0,
    50.0,
    200.0,
    80.0
  ]


def test_max_drawdown():
  equity_curve = [
    10000.0,
    10100.0,
    10050.0,
    9900.0,
    10020.0
  ]

  assert calculate_max_drawdown(equity_curve) == 200.0


def test_empty_equity_curve():
  assert calculate_drawdown_curve([]) == []
  assert calculate_max_drawdown([]) == 0.0


def run_tests():
  test_drawdown_curve()
  print("PASS: drawdown curve")

  test_max_drawdown()
  print("PASS: max drawdown")

  test_empty_equity_curve()
  print("PASS: empty equity curve")

  print()
  print("All Drawdown tests passed")


if __name__ == "__main__":
  run_tests()
