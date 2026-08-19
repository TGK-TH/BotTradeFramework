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
#include <BotTrade/Types/CdcLookalikeAccount2/Pattern.mqh>

CTrade trade;

//======================
// Inputs
//======================
input int    FastEMA = 12;
input int    SlowEMA = 26;

input double RetracementMin = 61.8;
input double RetracementMax = 100.0;

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

Pattern currentPattern;

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
  bool isGreen = false;

  if (GetEMAByHandle(fastHandle, 0, emaFast) && GetEMAByHandle(slowHandle, 0, emaSlow)) {
    isGreen = emaFast > emaSlow;
  }

  InitializeSegment(
    currentBarIndex,
    iHigh(_Symbol, PERIOD_CURRENT, 0),
    iLow(_Symbol, PERIOD_CURRENT, 0),
    isGreen
  );

  currentPattern.valid = false;
  currentPattern.isBuy = true;

  currentPattern.point1 = EMPTY_VALUE;
  currentPattern.point2 = EMPTY_VALUE;
  currentPattern.point3 = EMPTY_VALUE;

  currentPattern.point1Bar = -1;
  currentPattern.point2Bar = -1;
  currentPattern.point3Bar = -1;

  currentPattern.retracement = EMPTY_VALUE;

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

      if (greenCross) BuildBuyPattern(currentPattern);
      if (redCross) BuildSellPattern(currentPattern);

      // =======================
      // DEBUG
      // =======================
      if (greenCross) {
        Print("BUY Pattern Check");
        Print("L1 : ", currentPattern.point1);
        Print("H1 : ", currentPattern.point2);
        Print("L2 : ", currentPattern.point3);
        Print("Retracement : ", currentPattern.retracement);
        Print("Higher Low : ", currentPattern.point3 > currentPattern.point1);
        Print("Result : ", currentPattern.valid);
      }

      if (redCross) {
        Print("SELL Pattern Check");
        Print("H1 : ", currentPattern.point1);
        Print("L1 : ", currentPattern.point2);
        Print("H2 : ", currentPattern.point3);
        Print("Retracement : ", currentPattern.retracement);
        Print("Lower High : ", currentPattern.point3 < currentPattern.point1);
        Print("Result : ", currentPattern.valid);
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

//==================================================
// BUILD BUY PATTERN
//==================================================
void BuildBuyPattern(Pattern &result) {
  //==================================================
  // Default Result
  //==================================================
  result.valid = false;
  result.isBuy = true;

  result.point1 = EMPTY_VALUE;
  result.point2 = EMPTY_VALUE;
  result.point3 = EMPTY_VALUE;

  result.point1Bar = -1;
  result.point2Bar = -1;
  result.point3Bar = -1;

  result.retracement = EMPTY_VALUE;

  //==================================================
  // Need at least 3 segments
  //==================================================
  if (!HasEnoughSegments(3)) return;

  //==================================================
  // Get S0 / S1 / S2
  //
  // S0 = Latest
  // S1 = Previous
  // S2 = Previous of Previous
  //==================================================
  Segment s0, s1, s2;
  if (!(GetSegment(0, s0) && GetSegment(1, s1) && GetSegment(2, s2)))
    return;

  //==================================================
  // Pattern:
  //
  // S2 = Red
  // S1 = Green
  // S0 = Red
  //==================================================
  bool correctSequence = !s2.isGreen && s1.isGreen && !s0.isGreen;
  if (!correctSequence) return;

  //==================================================
  // BUY Points
  //
  // L1 = S2 Lowest
  // H1 = S1 Highest
  // L2 = S0 Lowest
  //==================================================
  double low1 = s2.lowest;
  double high1 = s1.highest;
  double low2 = s0.lowest;

  int low1Bar = s2.lowestBar;
  int high1Bar = s1.highestBar;
  int low2Bar = s0.lowestBar;

  //==================================================
  // Higher Low
  //==================================================
  bool higherLow = low2 > low1;

  //==================================================
  // Range
  //==================================================
  double L1H1Range = high1 - low1;
  if (L1H1Range <= 0.0) return;

  //==================================================
  // Retracement
  //==================================================
  double retracement = (high1 - low2) / L1H1Range * 100.0;

  //==================================================
  // Valid Pattern
  //==================================================
  bool valid =
    higherLow &&
    retracement >= RetracementMin &&
    retracement <= RetracementMax;

  //==================================================
  // Save Result
  //==================================================
  result.valid = valid;
  result.isBuy = true;

  result.point1 = low1;
  result.point2 = high1;
  result.point3 = low2;

  result.point1Bar = low1Bar;
  result.point2Bar = high1Bar;
  result.point3Bar = low2Bar;

  result.retracement = retracement;
} // END OF BuildBuyPattern

//==================================================
// BUILD SELL PATTERN
//==================================================
void BuildSellPattern(Pattern &result) {
  //==================================================
  // Default Result
  //==================================================
  result.valid = false;
  result.isBuy = false;

  result.point1 = EMPTY_VALUE;
  result.point2 = EMPTY_VALUE;
  result.point3 = EMPTY_VALUE;

  result.point1Bar = -1;
  result.point2Bar = -1;
  result.point3Bar = -1;

  result.retracement = EMPTY_VALUE;

  //==================================================
  // Need at least 3 segments
  //==================================================
  if (!HasEnoughSegments(3)) return;

  //==================================================
  // Get S0 / S1 / S2
  //
  // S0 = Latest
  // S1 = Previous
  // S2 = Previous of Previous
  //==================================================
  Segment s0, s1, s2;
  if (!(GetSegment(0, s0) && GetSegment(1, s1) && GetSegment(2, s2)))
    return;

  //==================================================
  // Pattern:
  //
  // S2 = Green
  // S1 = Red
  // S0 = Green
  //==================================================
  bool correctSequence = s2.isGreen && !s1.isGreen && s0.isGreen;
  if (!correctSequence) return;

  //==================================================
  // SELL Points
  //
  // H1 = S2 Highest
  // L1 = S1 Lowest
  // H2 = S0 Highest
  //==================================================
  double high1 = s2.highest;
  double low1 = s1.lowest;
  double high2 = s0.highest;

  int high1Bar = s2.highestBar;
  int low1Bar = s1.lowestBar;
  int high2Bar = s0.highestBar;

  //==================================================
  // Lower High
  //==================================================
  bool lowerHigh = high2 < high1;

  //==================================================
  // Range
  //==================================================
  double H1L1Range = high1 - low1;
  if (H1L1Range <= 0.0) return;

  //==================================================
  // Retracement
  //==================================================
  double retracement = (high2 - low1) / H1L1Range * 100.0;

  //==================================================
  // Valid Pattern
  //==================================================
  bool valid =
    lowerHigh &&
    retracement >= RetracementMin &&
    retracement <= RetracementMax;

  //==================================================
  // Save Result
  //==================================================
  result.valid = valid;
  result.isBuy = false;

  result.point1 = high1;
  result.point2 = low1;
  result.point3 = high2;

  result.point1Bar = high1Bar;
  result.point2Bar = low1Bar;
  result.point3Bar = high2Bar;

  result.retracement = retracement;
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

  double tradeSL = 0.0;
  if (isBuy) {
    tradeSL = currentPattern.valid
      ? currentPattern.point3 - SLBuffer
      : LastPivotLow(_Symbol, PERIOD_CURRENT) - SLBuffer;
  } else {
    tradeSL = currentPattern.valid
      ? currentPattern.point3 + SLBuffer
      : LastPivotHigh(_Symbol, PERIOD_CURRENT) + SLBuffer;
  }

  double price = SymbolInfoDouble(
    _Symbol,
    isBuy ? SYMBOL_ASK : SYMBOL_BID
  );

  double lot = CalcLot(
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
