//+------------------------------------------------------------------+
//|                                    CDC_Lookalike_Account_2.mq5   |
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

#include <BotTrade/Types/CdcLookalikeAccount2/Segment.mqh>

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

input long MagicNumber = 3004;
input int  RetrySeconds = 5;

//======================
// Variables
//======================
datetime lastBarTime = 0;

int fastHandle;
int slowHandle;

CTargetPositionReconciler positionReconciler;

Segment segments[];

int currentBarIndex = -1;
bool greenCross = false;
bool redCross = false;
bool crossHappened = false;

//==================================================
// CURRENT SEGMENT
//==================================================
int segStart = -1;

double currentHigh = 0.0;
double currentLow = 0.0;

int currentHighBar = -1;
int currentLowBar = -1;

bool currentIsGreen = false;

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

  positionReconciler.Initialize(
    _Symbol,
    MagicNumber,
    "CDCLOOKACC2",
    RetrySeconds
  );
  positionReconciler.Restore();

  // Do not execute a historical cross when the EA is attached mid-bar.
  lastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

  double emaFast;
  double emaSlow;
  if(!GetEMAByHandle(fastHandle, 0, emaFast) ||
     !GetEMAByHandle(slowHandle, 0, emaSlow))
    return(INIT_FAILED);

  InitializeSegment(
    currentBarIndex,
    iHigh(_Symbol, PERIOD_CURRENT, 0),
    iLow(_Symbol, PERIOD_CURRENT, 0),
    emaFast > emaSlow
  );

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

  // Signals use closed candles and are evaluated only once per new candle.
  if (currentBar != 0 && currentBar != lastBarTime) {
    lastBarTime = currentBar;
    currentBarIndex += 1;
    double barHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double barLow = iLow(_Symbol, PERIOD_CURRENT, 1);

    UpdateCurrentSegment(
      currentBarIndex,
      barHigh,
      barLow
    );

    greenCross = IsEmaCrossUpByHandle(fastHandle, slowHandle);
    redCross = IsEmaCrossDownByHandle(fastHandle, slowHandle);

    crossHappened = greenCross || redCross;

    if (crossHappened) {
      SaveCurrentSegment(
        currentBarIndex,
        barHigh,
        barLow
      );

      Segment s0;
      Segment s1;
      Segment s2;

      if (GetSegment(0, s0) && GetSegment(1, s1) && GetSegment(2, s2)) {
        // print log there enough segments
        Print("Segment 0: StartBar=", s0.startBar, ", EndBar=", s0.endBar, ", CrossBar=", s0.crossBar, ", Highest=", s0.highest, ", HighestBar=", s0.highestBar, ", Lowest=", s0.lowest, ", LowestBar=", s0.lowestBar, ", IsGreen=", s0.isGreen);
        Print("Segment 1: StartBar=", s1.startBar, ", EndBar=", s1.endBar, ", CrossBar=", s1.crossBar, ", Highest=", s1.highest, ", HighestBar=", s1.highestBar, ", Lowest=", s1.lowest, ", LowestBar=", s1.lowestBar, ", IsGreen=", s1.isGreen);
        Print("Segment 2: StartBar=", s2.startBar, ", EndBar=", s2.endBar, ", CrossBar=", s2.crossBar, ", Highest=", s2.highest, ", HighestBar=", s2.highestBar, ", Lowest=", s2.lowest, ", LowestBar=", s2.lowestBar, ", IsGreen=", s2.isGreen);
      }

      CheckSignal(iTime(_Symbol, PERIOD_CURRENT, 1));
    } // End of cross happened check
  } // End of new bar check

  ReconcilePosition();
}

//==================================================
// INITIALIZE SEGMENT
//==================================================

void InitializeSegment(
  int barIndex,
  double barHigh,
  double barLow,
  bool isGreen
) {
    segStart = barIndex;

    currentHigh = barHigh;
    currentLow = barLow;

    currentHighBar = barIndex;
    currentLowBar = barIndex;

    currentIsGreen = isGreen;
}

//==================================================
// UPDATE CURRENT SEGMENT
//==================================================
void UpdateCurrentSegment(
  int barIndex,
  double barHigh,
  double barLow
) {
  if (barHigh > currentHigh) {
    currentHigh = barHigh;
    currentHighBar = barIndex;
  }

  if (barLow < currentLow) {
    currentLow = barLow;
    currentLowBar = barIndex;
  }
}

//==================================================
// SAVE SEGMENT
//==================================================
void SaveCurrentSegment(
   int barIndex,
   double barHigh,
   double barLow
) {
   //==================================================
   // Save Previous Segment
   //==================================================
   Segment newSegment;

   newSegment.startBar = segStart;
   newSegment.endBar = barIndex - 1;
   newSegment.crossBar = barIndex;

   newSegment.highest = currentHigh;
   newSegment.highestBar = currentHighBar;

   newSegment.lowest = currentLow;
   newSegment.lowestBar = currentLowBar;

   newSegment.isGreen = currentIsGreen;

   int newSize = ArraySize(segments) + 1;
   ArrayResize(segments, newSize);

   segments[newSize - 1] = newSegment;

   //==================================================
   // Start Next Segment
   //==================================================
   segStart = barIndex;

   currentHigh = barHigh;
   currentHighBar = barIndex;

   currentLow = barLow;
   currentLowBar = barIndex;

   currentIsGreen = greenCross;
}

//==================================================
// SEGMENT FUNCTIONS
//==================================================
bool GetSegment(int offset, Segment &result) {
   int count = ArraySize(segments);

   if (count <= offset)
      return false;

   int index = count - 1 - offset;
   result = segments[index];

   return true;
}

bool HasEnoughSegments(int count) {
   return ArraySize(segments) >= count;
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

   positionReconciler.CancelIfTrendChanged(
    fastEma > slowEma,
    fastEma < slowEma
  );
}

//+------------------------------------------------------------------+
//| Build order parameters using current price immediately before    |
//| execution, then ask the common reconciler to reach the target.   |
//+------------------------------------------------------------------+
void ReconcilePosition() {
  ValidatePendingTrend();

  ENUM_DESIRED_POSITION target = positionReconciler.Target();
  if (target == DESIRED_POSITION_NONE)
    return;

  bool isBuy = target == DESIRED_POSITION_BUY;
  double tradeSL = isBuy
                   ? LastPivotLow(_Symbol, PERIOD_CURRENT) - SLBuffer
                   : LastPivotHigh(_Symbol, PERIOD_CURRENT) + SLBuffer;
  double price = SymbolInfoDouble(
    _Symbol,
    isBuy ? SYMBOL_ASK : SYMBOL_BID
  );
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
  if (greenCross) {
    positionReconciler.SetTarget(
      DESIRED_POSITION_BUY,
      signalBarTime
    );
    return;
  }

  // SELL Signal
  if (redCross) {
    positionReconciler.SetTarget(
      DESIRED_POSITION_SELL,
      signalBarTime
    );
    return;
  }
}
