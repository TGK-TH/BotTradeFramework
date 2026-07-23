#ifndef __BOT_CONTEXT_MQH__
#define __BOT_CONTEXT_MQH__

#include "TradeState.mqh"
#include "Candle.mqh"

struct BotContext {
   TradeState State;
   Candle     A;

   double TradeSL;
   double TradeTP;

   double EntryPrice;
   double InitialRisk;

   bool TrendMode;

   double CurrentLot;
};

#endif
