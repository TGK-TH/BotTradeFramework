//+------------------------------------------------------------------+
//|                                               EMA Cross EA.mq5   |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

#include <BotTrade/Indicators/EMA.mqh>
#include <BotTrade/Indicators/Pivot.mqh>

#include <BotTrade/Risk/LotCalculator.mqh>

CTrade trade;

//======================
// Inputs
//======================
input int    FastEMA = 12;
input int    SlowEMA = 26;

input bool IsFixedLot = true;
input double FixedLotValue = 0.10;

input double RiskUSD = 1000;
input double MaxLot = 100.0;
input double SLBuffer = 1.5;

//======================
// Variables
//======================
datetime lastBarTime = 0;

int fastHandle;
int slowHandle;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   fastHandle = iMA(_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_CURRENT, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
}

//+------------------------------------------------------------------+
//| Expert Tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // Run only once per candle
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

   if(currentBar == lastBarTime)
      return;

   lastBarTime = currentBar;

   CheckSignal();
}

//+------------------------------------------------------------------+
//| Check EMA Cross Up                                               |
//+------------------------------------------------------------------+
bool isCrossUp() {
  double emaFastPrev = GetEMA(_Symbol, PERIOD_CURRENT, FastEMA, 2);
  double emaSlowPrev = GetEMA(_Symbol, PERIOD_CURRENT, SlowEMA, 2);
  double emaFastCurr = GetEMA(_Symbol, PERIOD_CURRENT, FastEMA, 1);
  double emaSlowCurr = GetEMA(_Symbol, PERIOD_CURRENT, SlowEMA, 1);

  return emaFastPrev <= emaSlowPrev && emaFastCurr > emaSlowCurr;
}

//+------------------------------------------------------------------+
//| Check EMA Cross Down                                             |
//+------------------------------------------------------------------+
bool isCrossDown() {
  double emaFastPrev = GetEMA(_Symbol, PERIOD_CURRENT, FastEMA, 2);
  double emaSlowPrev = GetEMA(_Symbol, PERIOD_CURRENT, SlowEMA, 2);
  double emaFastCurr = GetEMA(_Symbol, PERIOD_CURRENT, FastEMA, 1);
  double emaSlowCurr = GetEMA(_Symbol, PERIOD_CURRENT, SlowEMA, 1);

  return emaFastPrev >= emaSlowPrev && emaFastCurr < emaSlowCurr;
}

//+------------------------------------------------------------------+
//| Check EMA Cross                                                  |
//+------------------------------------------------------------------+
void CheckSignal()
{
   // BUY Signal
   if(isCrossUp()) {
      double tradeSL = LastPivotLow(_Symbol, PERIOD_CURRENT) - SLBuffer;

      double buyQty = IsFixedLot ?
         FixedLotValue :
         CalcLot(
            _Symbol,
            ORDER_TYPE_BUY,
            SymbolInfoDouble(_Symbol, SYMBOL_ASK), tradeSL,
            RiskUSD,
            MaxLot
         );

      ClosePosition(POSITION_TYPE_SELL);

      if(!PositionSelect(_Symbol)) {
         trade.Buy(buyQty);
      }
   }

   // SELL Signal
   if(isCrossDown()) {
      double tradeSL = LastPivotHigh(_Symbol, PERIOD_CURRENT) + SLBuffer;

      double sellQty = IsFixedLot ?
         FixedLotValue :
         CalcLot(
            _Symbol,
            ORDER_TYPE_SELL,
            SymbolInfoDouble(_Symbol, SYMBOL_BID), tradeSL,
            RiskUSD,
            MaxLot
         );

      ClosePosition(POSITION_TYPE_BUY);

      if(!PositionSelect(_Symbol))
      {
         trade.Sell(sellQty);
      }
   }
}

//+------------------------------------------------------------------+
//| Close Position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(ENUM_POSITION_TYPE type)
{
   if(!PositionSelect(_Symbol))
      return;

   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
   {
      trade.PositionClose(_Symbol);
   }
}
