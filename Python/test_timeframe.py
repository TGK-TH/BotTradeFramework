from tgk_trading.domain.timeframe import Timeframe


def test_timeframe_values():
  assert Timeframe.M1.value == "M1"
  assert Timeframe.M15.value == "M15"
  assert Timeframe.H1.value == "H1"
  assert Timeframe.H4.value == "H4"
