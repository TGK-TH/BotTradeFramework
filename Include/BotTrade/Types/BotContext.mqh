#ifndef __BOT_CONTEXT_MQH__
#define __BOT_CONTEXT_MQH__

#include "TradeState.mqh"
#include "Candle.mqh"

struct BotContext
{
   TradeState State;
   Candle     A;
};

#endif
