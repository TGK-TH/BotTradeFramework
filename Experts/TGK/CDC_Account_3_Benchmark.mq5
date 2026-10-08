//+------------------------------------------------------------------+
//|                                               EMA Cross EA.mq5   |
//+------------------------------------------------------------------+
#property strict

enum ENUM_POSITION_MODE {
   POSITION_MODE_SINGLE = 0,
   POSITION_MODE_THREE = 1
};

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

input ENUM_POSITION_MODE PositionMode = POSITION_MODE_SINGLE;

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

ENUM_DESIRED_POSITION threeTarget = DESIRED_POSITION_NONE;

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
   RestoreThreeTarget();

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
struct STradeParameters {
   bool isBuy;
   double entryPrice;
   double tradeSL;
   double riskDistance;
   double totalLot;
};

struct SThreeLotSplit {
   bool isValid;
   double lot1;
   double lot2;
   double lot3;
};

struct SThreeTradePlan {
   bool isValid;
   bool isBuy;
   double entryPrice;
   double tradeSL;
   double riskDistance;
   double lot1;
   double lot2;
   double lot3;
   double tp1;
   double tp2;
};

bool SplitThreeLots(double totalLot, SThreeLotSplit &split) {
   split.isValid = false;
   split.lot1 = 0;
   split.lot2 = 0;
   split.lot3 = 0;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(minLot <= 0 || lotStep <= 0 || totalLot < minLot * 3)
      return false;

   double baseLot = MathFloor(totalLot / 3.0 / lotStep) * lotStep;
   baseLot = NormalizeDouble(baseLot, 2);

   if(baseLot < minLot)
      return false;

   double lot1 = totalLot - baseLot * 2.0;
   lot1 = NormalizeDouble(lot1, 2);

   if(lot1 < minLot)
      return false;

   double reconstructedTotal = NormalizeDouble(lot1 + baseLot + baseLot, 2);
   double totalDifference = MathAbs(reconstructedTotal - NormalizeDouble(totalLot, 2));

   if(totalDifference > lotStep / 2.0)
      return false;

   split.isValid = true;
   split.lot1 = lot1;
   split.lot2 = baseLot;
   split.lot3 = baseLot;
   return true;
}

bool BuildThreeTradePlan(ENUM_DESIRED_POSITION target, SThreeTradePlan &plan) {
   plan.isValid = false;
   plan.isBuy = target == DESIRED_POSITION_BUY;
   plan.entryPrice = 0;
   plan.tradeSL = 0;
   plan.riskDistance = 0;
   plan.lot1 = 0;
   plan.lot2 = 0;
   plan.lot3 = 0;
   plan.tp1 = 0;
   plan.tp2 = 0;

   if(PositionMode != POSITION_MODE_THREE || IsFixedLot)
      return false;

   STradeParameters parameters;
   if(!BuildTradeParameters(target, parameters))
      return false;

   SThreeLotSplit split;
   if(!SplitThreeLots(parameters.totalLot, split))
      return false;

   plan.isBuy = parameters.isBuy;
   plan.entryPrice = parameters.entryPrice;
   plan.tradeSL = parameters.tradeSL;
   plan.riskDistance = parameters.riskDistance;
   plan.lot1 = split.lot1;
   plan.lot2 = split.lot2;
   plan.lot3 = split.lot3;

   plan.tp1 = plan.isBuy
              ? plan.entryPrice + plan.riskDistance
              : plan.entryPrice - plan.riskDistance;
   plan.tp2 = plan.isBuy
              ? plan.entryPrice + plan.riskDistance * 2.0
              : plan.entryPrice - plan.riskDistance * 2.0;

   plan.isValid = true;
   return true;
}

ENUM_DESIRED_POSITION DetectThreeTarget() {
   bool hasBuy = HasPositionOfType(_Symbol, MagicNumber, POSITION_TYPE_BUY);
   bool hasSell = HasPositionOfType(_Symbol, MagicNumber, POSITION_TYPE_SELL);

   if(hasBuy && !hasSell)
      return DESIRED_POSITION_BUY;

   if(hasSell && !hasBuy)
      return DESIRED_POSITION_SELL;

   return DESIRED_POSITION_NONE;
}

void RestoreThreeTarget() {
   threeTarget = DESIRED_POSITION_NONE;

   if(PositionMode != POSITION_MODE_THREE || IsFixedLot)
      return;

   threeTarget = DetectThreeTarget();
}


bool HasPositionWithComment(string comment) {
   for(int index = PositionsTotal() - 1; index >= 0; index--) {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_COMMENT) == comment)
         return true;
   }

   return false;
}

bool ExecuteThreeTradePlan(const SThreeTradePlan &plan) {
   if(!plan.isValid)
      return false;

   if(plan.isBuy && HasPositionOfType(_Symbol, MagicNumber, POSITION_TYPE_SELL))
      return false;

   if(!plan.isBuy && HasPositionOfType(_Symbol, MagicNumber, POSITION_TYPE_BUY))
      return false;

   double sl = SetSlAtLastPivot ? plan.tradeSL : 0;
   bool allExecuted = true;

   if(!HasPositionWithComment("CDC3-1")) {
      bool sent = plan.isBuy
                  ? ExecuteBuy(trade, _Symbol, plan.lot1, sl, plan.tp1, "CDC3-1")
                  : ExecuteSell(trade, _Symbol, plan.lot1, sl, plan.tp1, "CDC3-1");
      if(!sent)
         allExecuted = false;
   }

   if(!HasPositionWithComment("CDC3-2")) {
      bool sent = plan.isBuy
                  ? ExecuteBuy(trade, _Symbol, plan.lot2, sl, plan.tp2, "CDC3-2")
                  : ExecuteSell(trade, _Symbol, plan.lot2, sl, plan.tp2, "CDC3-2");
      if(!sent)
         allExecuted = false;
   }

   if(!HasPositionWithComment("CDC3-3")) {
      bool sent = plan.isBuy
                  ? ExecuteBuy(trade, _Symbol, plan.lot3, sl, 0, "CDC3-3")
                  : ExecuteSell(trade, _Symbol, plan.lot3, sl, 0, "CDC3-3");
      if(!sent)
         allExecuted = false;
   }

   return allExecuted;
}

bool BuildTradeParameters(ENUM_DESIRED_POSITION target, STradeParameters &parameters) {
   parameters.isBuy = target == DESIRED_POSITION_BUY;
   parameters.entryPrice = SymbolInfoDouble(_Symbol, parameters.isBuy ? SYMBOL_ASK : SYMBOL_BID);
   parameters.tradeSL = parameters.isBuy
                        ? LastPivotLow(_Symbol, PERIOD_CURRENT) - SLBuffer
                        : LastPivotHigh(_Symbol, PERIOD_CURRENT) + SLBuffer;

   parameters.riskDistance = parameters.isBuy
                             ? parameters.entryPrice - parameters.tradeSL
                             : parameters.tradeSL - parameters.entryPrice;

   if(parameters.riskDistance <= 0)
      return false;

   parameters.totalLot = IsFixedLot
                         ? FixedLotValue
                         : CalcLot(
                              _Symbol,
                              parameters.isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                              parameters.entryPrice,
                              parameters.tradeSL,
                              RiskUSD,
                              MaxLot
                           );

   return parameters.totalLot > 0;
}

void ReconcilePosition() {
   if(PositionMode == POSITION_MODE_THREE && !IsFixedLot &&
      threeTarget != DESIRED_POSITION_NONE) {
      SThreeTradePlan plan;
      if(!BuildThreeTradePlan(threeTarget, plan)) {
         positionReconciler.SetTarget(threeTarget, TimeCurrent());
         threeTarget = DESIRED_POSITION_NONE;
         return;
      }

      if(ExecuteThreeTradePlan(plan))
         threeTarget = DESIRED_POSITION_NONE;

      return;
   }

   ValidatePendingTrend();

   ENUM_DESIRED_POSITION target = positionReconciler.Target();
   if(target == DESIRED_POSITION_NONE)
      return;

   STradeParameters parameters;
   if(!BuildTradeParameters(target, parameters))
      return;

   positionReconciler.Reconcile(
      trade,
      parameters.totalLot,
      SetSlAtLastPivot ? parameters.tradeSL : 0,
      0,
      parameters.isBuy ? "BUY" : "SELL"
   );
}

//+------------------------------------------------------------------+
//| Check EMA Cross                                                  |
//+------------------------------------------------------------------+
void CheckSignal(datetime signalBarTime) {
   bool useThreeMode = PositionMode == POSITION_MODE_THREE && !IsFixedLot;

   // BUY Signal
   if(IsEmaCrossUpByHandle(fastHandle, slowHandle)) {
      if(useThreeMode) {
         ClosePositions(trade, _Symbol, MagicNumber, POSITION_TYPE_SELL);
         threeTarget = DESIRED_POSITION_BUY;
      }
      else {
         positionReconciler.SetTarget(DESIRED_POSITION_BUY, signalBarTime);
      }
      return;
   }

   // SELL Signal
   if(IsEmaCrossDownByHandle(fastHandle, slowHandle)) {
      if(useThreeMode) {
         ClosePositions(trade, _Symbol, MagicNumber, POSITION_TYPE_BUY);
         threeTarget = DESIRED_POSITION_SELL;
      }
      else {
         positionReconciler.SetTarget(DESIRED_POSITION_SELL, signalBarTime);
      }
   }
}
