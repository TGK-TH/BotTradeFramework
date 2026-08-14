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

#include <BotTrade/Trade/OrderExecution.mqh>
#include <BotTrade/Trade/TargetPositionReconciler.mqh>

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

input long MagicNumber = 3003;
input int  RetrySeconds = 5;

//======================
// Variables
//======================
datetime lastBarTime = 0;

int fastHandle;
int slowHandle;

CTargetPositionReconciler positionReconciler;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
   fastHandle = iMA(_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_CURRENT, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   trade.SetExpertMagicNumber((ulong)MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   positionReconciler.Initialize(_Symbol, MagicNumber, "CDC3EMA", RetrySeconds);
   positionReconciler.Restore();

   // Do not execute a historical cross when the EA is attached mid-bar.
   lastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

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
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

   // Signals use closed candles and are evaluated only once per new candle.
   if(currentBar != 0 && currentBar != lastBarTime) {
      lastBarTime = currentBar;
      CheckSignal(iTime(_Symbol, PERIOD_CURRENT, 1));
   }

   ReconcilePosition();
}

//+------------------------------------------------------------------+
//| Confirm that a pending target still agrees with the last closed  |
//| candle. This runs on every tick so a target retained through a   |
//| market break is checked before it is executed at market reopen.  |
//+------------------------------------------------------------------+
void ValidatePendingTrend() {
   if(positionReconciler.Target() == DESIRED_POSITION_NONE)
      return;

   double fastEma;
   double slowEma;
   if(!GetEMAByHandle(fastHandle, 1, fastEma) ||
      !GetEMAByHandle(slowHandle, 1, slowEma))
      return;

   positionReconciler.CancelIfTrendChanged(fastEma > slowEma, fastEma < slowEma);
}

//+------------------------------------------------------------------+
//| Build order parameters using current price immediately before    |
//| execution, then ask the common reconciler to reach the target.   |
//+------------------------------------------------------------------+
void ReconcilePosition() {
   ValidatePendingTrend();

   ENUM_DESIRED_POSITION target = positionReconciler.Target();
   if(target == DESIRED_POSITION_NONE)
      return;

   bool isBuy = target == DESIRED_POSITION_BUY;
   double tradeSL = isBuy
                    ? LastPivotLow(_Symbol, PERIOD_CURRENT) - SLBuffer
                    : LastPivotHigh(_Symbol, PERIOD_CURRENT) + SLBuffer;
   double price = SymbolInfoDouble(_Symbol, isBuy ? SYMBOL_ASK : SYMBOL_BID);
   double lot = IsFixedLot
                ? FixedLotValue
                : CalcLot(
                     _Symbol,
                     isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                     price,
                     tradeSL,
                     RiskUSD,
                     MaxLot
                  );

   positionReconciler.Reconcile(
      trade,
      lot,
      SetSlAtLastPivot ? tradeSL : 0,
      0,
      isBuy ? "BUY" : "SELL"
   );
}

//+------------------------------------------------------------------+
//| Check EMA Cross                                                  |
//+------------------------------------------------------------------+
void CheckSignal(datetime signalBarTime) {
   // BUY Signal
   if(IsEmaCrossUpByHandle(fastHandle, slowHandle)) {
      positionReconciler.SetTarget(DESIRED_POSITION_BUY, signalBarTime);
      return;
   }

   // SELL Signal
   if(IsEmaCrossDownByHandle(fastHandle, slowHandle)) {
      positionReconciler.SetTarget(DESIRED_POSITION_SELL, signalBarTime);
   }
}
