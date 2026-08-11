//+------------------------------------------------------------------+
//|                                               EMA Cross EA.mq5   |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

#include <BotTrade/Indicators/EMA.mqh>
#include <BotTrade/Indicators/Pivot.mqh>

#include <BotTrade/Position/Position.mqh>

#include <BotTrade/Risk/LotCalculator.mqh>

#include <BotTrade/Strategy/EmaCross/IsEmaCrossUp.mqh>
#include <BotTrade/Strategy/EmaCross/IsEmaCrossDown.mqh>

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

input bool SetSlAtLastPivot = false;

//======================
// Variables
//======================
datetime lastBarTime = 0;

int fastHandle;
int slowHandle;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
   fastHandle = iMA(_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_CURRENT, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
}

//+------------------------------------------------------------------+
//| Expert Tick                                                      |
//+------------------------------------------------------------------+
void OnTick() {
   // Run only once per candle
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

   if(currentBar == lastBarTime)
      return;

   lastBarTime = currentBar;

   CheckSignal();
}

//+------------------------------------------------------------------+
//| Check EMA Cross                                                  |
//+------------------------------------------------------------------+
void CheckSignal() {
   // BUY Signal
   if(IsEmaCrossUp(_Symbol, PERIOD_CURRENT, FastEMA, SlowEMA)) {
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

      ClosePosition(trade, _Symbol, POSITION_TYPE_SELL);

      if(!HasPosition()) {
         trade.Buy(
            buyQty,
            _Symbol,
            0,
            SetSlAtLastPivot ? tradeSL : 0,
            0,
            "BUY"
         );
      }
   }

   // SELL Signal
   if(IsEmaCrossDown(_Symbol, PERIOD_CURRENT, FastEMA, SlowEMA)) {
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

      ClosePosition(trade, _Symbol, POSITION_TYPE_BUY);

      if(!HasPosition()) {
         trade.Sell(
            sellQty,
            _Symbol,
            0,
            SetSlAtLastPivot ? tradeSL : 0,
            0,
            "SELL"
         );
      }
   }
}
