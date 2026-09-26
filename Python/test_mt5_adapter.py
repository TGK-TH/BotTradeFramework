from tgk_trading.brokers.mt5 import MT5Adapter


class FakeMT5:
  def __init__(self, initialize_result=True):
    self.initialize_result = initialize_result
    self.initialize_calls = 0
    self.shutdown_calls = 0

  def initialize(self):
    self.initialize_calls += 1
    return self.initialize_result

  def shutdown(self):
    self.shutdown_calls += 1

  def last_error(self):
    return (10000, "Fake error")


def test_connect_initializes_mt5():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)

  adapter.connect()

  assert adapter.is_connected()
  assert mt5.initialize_calls == 1


def test_connect_does_not_initialize_twice():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)

  adapter.connect()
  adapter.connect()

  assert mt5.initialize_calls == 1


def test_disconnect_shuts_down_mt5():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)

  adapter.connect()
  adapter.disconnect()

  assert not adapter.is_connected()
  assert mt5.shutdown_calls == 1


def test_disconnect_does_nothing_when_not_connected():
  mt5 = FakeMT5()
  adapter = MT5Adapter(mt5)

  adapter.disconnect()

  assert mt5.shutdown_calls == 0


def test_connect_raises_when_mt5_initialize_fails():
  mt5 = FakeMT5(initialize_result=False)
  adapter = MT5Adapter(mt5)

  try:
    adapter.connect()
    assert False, "Expected RuntimeError"
  except RuntimeError as error:
    assert "MT5 initialize failed" in str(error)
