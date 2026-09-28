from tgk_trading.domain.order import Order, OrderSide, OrderType
from tgk_trading.live.order_executor import RecordingOrderExecutor


def test_recording_order_executor_records_orders():
  executor = RecordingOrderExecutor()
  order = Order(
    type=OrderType.MARKET,
    side=OrderSide.BUY,
    quantity=1.0
  )

  executor.submit_order(order)

  assert executor.orders == [order]
