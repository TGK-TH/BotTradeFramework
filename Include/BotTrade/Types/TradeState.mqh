#ifndef __TRADE_STATE_MQH__
#define __TRADE_STATE_MQH__

enum TradeState
{
  STATE_WAIT_CROSS = 0,
  STATE_WAIT_RETEST,
  STATE_WAIT_A,
  STATE_WAIT_B,
  STATE_IN_TRADE
};

#endif
