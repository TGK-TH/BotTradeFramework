//+------------------------------------------------------------------+
//| EMA Cross Retest Framework - Phase 1                            |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

#include <BotTrade/Indicators/EMA.mqh>
#include <BotTrade/Indicators/ADX.mqh>
#include <BotTrade/Indicators/Pivot.mqh>

#include <BotTrade/Market/Bar.mqh>

#include <BotTrade/Position/Position.mqh>

#include <BotTrade/Risk/LotCalculator.mqh>

#include <BotTrade/Strategy/StateMachine/WaitA.mqh>

#include <BotTrade/Trade/TrailingStop.mqh>

#include <BotTrade/Types/Candle.mqh>

CTrade trade;

//=====================================================
// INPUTS
//=====================================================

input int EMAFastLen = 12;
input int EMASlowLen = 26;

input int ADXPeriod = 14;
input double ADXThreshold = 20.0;
int ADXHandle;

input double RiskUSD = 1000;
input double MaxLot = 100.0;

input double SLBuffer = 1.5;

input double TrendTrailStartRR = 3.5;
input double TrendTrailStepRR = 0.5;

input double NonTrendTrailStartRR = 1.0;
input double NonTrendTrailStepRR = 0.5;

//=====================================================
// STATES
//=====================================================

enum ENUM_STATE
{
   STATE_WAIT_CROSS = 0,
   STATE_WAIT_RETEST,
   STATE_WAIT_A,
   STATE_WAIT_B,
   STATE_IN_TRADE
};

ENUM_STATE State = STATE_WAIT_CROSS;

//=====================================================
// DIRECTION
//=====================================================

enum ENUM_DIRECTION
{
   DIR_NONE = 0,
   DIR_BUY = 1,
   DIR_SELL = -1
};

ENUM_DIRECTION Direction = DIR_NONE;

//=====================================================
// GLOBALS
//=====================================================

datetime LastM15Bar = 0;

//=====================================================
// A CANDLE VARIABLES
//=====================================================

Candle A;

/*
double AHigh = 0;
double ALow = 0;

datetime ABarTime = 0;
*/

double TradeSL = 0;
double TradeTP = 0;

double EntryPrice = 0;
double InitialRisk = 0;

bool TrendMode = false;

double CurrentLot = 0;

//=====================================================
// H1 CROSS
//=====================================================

bool H1CrossUp()
{
   double ema12_prev =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 2);

   double ema26_prev =
      GetEMA(_Symbol, PERIOD_H1, EMASlowLen, 2);

   double ema12_curr =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 1);

   double ema26_curr =
      GetEMA(_Symbol, PERIOD_H1, EMASlowLen, 1);

   return
      ema12_prev <= ema26_prev &&
      ema12_curr > ema26_curr;
}

//-----------------------------------------------------

bool H1CrossDown()
{
   double ema12_prev =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 2);

   double ema26_prev =
      GetEMA(_Symbol, PERIOD_H1, EMASlowLen, 2);

   double ema12_curr =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 1);

   double ema26_curr =
      GetEMA(_Symbol, PERIOD_H1, EMASlowLen, 1);

   return
      ema12_prev >= ema26_prev &&
      ema12_curr < ema26_curr;
}

//=====================================================
// RETEST
//=====================================================

bool BuyRetest()
{
   double lowM15 =
      iLow(_Symbol,PERIOD_M15,1);

   double h1EMA12 =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 1);

   return lowM15 < h1EMA12;
}

//-----------------------------------------------------

bool SellRetest()
{
   double highM15 =
      iHigh(_Symbol,PERIOD_M15,1);

   double h1EMA12 =
      GetEMA(_Symbol, PERIOD_H1, EMAFastLen, 1);

   return highM15 > h1EMA12;
}

//=====================================================
// CANDLE A
//=====================================================

bool BuyA()
{
   double closeM15 =
      iClose(_Symbol, PERIOD_M15, 1);

   double ema12 =
      GetEMA(_Symbol, PERIOD_M15, EMAFastLen, 1);

   double ema26 =
      GetEMA(_Symbol, PERIOD_M15, EMASlowLen, 1);

   double upperEMA = MathMax(ema12, ema26);

   return closeM15 > upperEMA;
}

//-----------------------------------------------------

bool SellA()
{
   double closeM15 =
      iClose(_Symbol, PERIOD_M15, 1);

   double ema12 =
      GetEMA(_Symbol, PERIOD_M15, EMAFastLen, 1);

   double ema26 =
      GetEMA(_Symbol, PERIOD_M15, EMASlowLen, 1);

   double lowerEMA = MathMin(ema12, ema26);

   return closeM15 < lowerEMA;
}

//=====================================================
// CANDLE B
//=====================================================

bool BuyB()
{
   double closeM15 =
      iClose(_Symbol, PERIOD_M15, 1);

   double lowM15 =
      iLow(_Symbol, PERIOD_M15, 1);

   return
      closeM15 > A.High &&
      lowM15 > A.Low;
}

//-----------------------------------------------------

bool SellB()
{
   double closeM15 =
      iClose(_Symbol, PERIOD_M15, 1);

   double highM15 =
      iHigh(_Symbol, PERIOD_M15, 1);

   return
      closeM15 < A.Low &&
      highM15 < A.High;
}

//=====================================================
// H4 TREND
//=====================================================

bool IsH4BullTrend()
{
   return
      GetEMA(_Symbol, PERIOD_H4, EMAFastLen, 1) >
      GetEMA(_Symbol, PERIOD_H4, EMASlowLen, 1);
}

//------------------------------------------------

bool IsH4BearTrend()
{
   return
      GetEMA(_Symbol, PERIOD_H4, EMAFastLen, 1) <
      GetEMA(_Symbol, PERIOD_H4, EMASlowLen, 1);
}

//=====================================================
// STATE MACHINE
//=====================================================

void ProcessStateMachine()
{
   //--------------------------------------------------
   // H1 CROSS
   //--------------------------------------------------

   if(H1CrossUp())
   {
      State = STATE_WAIT_RETEST;
      Direction = DIR_BUY;

      Print("H1 CROSS UP");
   }

   if(H1CrossDown())
   {
      State = STATE_WAIT_RETEST;
      Direction = DIR_SELL;

      Print("H1 CROSS DOWN");
   }

   //--------------------------------------------------
   // WAIT RETEST
   //--------------------------------------------------

   if(State == STATE_WAIT_RETEST)
   {
      datetime barTime = iTime(_Symbol, PERIOD_M15, 1);

      if(Direction == DIR_BUY)
      {
         if(BuyRetest())
         {
            State = STATE_WAIT_A;

            Print(
               "BUY RETEST DONE ON BAR ",
               TimeToString(barTime)
            );
         }
      }

      if(Direction == DIR_SELL)
      {
         if(SellRetest())
         {
            State = STATE_WAIT_A;

            Print(
               "SELL RETEST DONE ON BAR ",
               TimeToString(barTime)
            );
         }
      }
   }

   //--------------------------------------------------
   // WAIT A
   //--------------------------------------------------

   if(State == STATE_WAIT_A)
   {
      datetime barTime =
         iTime(_Symbol, PERIOD_M15, 1);

      if(Direction == DIR_BUY)
      {
         ProcessBuyWaitA();
      }

      if(Direction == DIR_SELL)
      {
         ProcessSellWaitA();
      }
   }

   //--------------------------------------------------
   // WAIT B
   //--------------------------------------------------

   if(State == STATE_WAIT_B) {
      bool adxBuy =
         GetADX(ADXHandle, 1) >= ADXThreshold &&
         GetDIPlus(ADXHandle, 1) > GetDIMinus(ADXHandle, 1);

      bool adxSell =
         GetADX(ADXHandle, 1) >= ADXThreshold &&
         GetDIMinus(ADXHandle, 1) > GetDIPlus(ADXHandle, 1);

      datetime currentBar = iTime(_Symbol, PERIOD_M15, 1);

      // B Must be next to A only
      if(currentBar > A.Time + PeriodSeconds(PERIOD_M15)) {
         State = STATE_WAIT_A;

         Print("B NOT FOUND -> BACK TO WAIT A");
      }
      else {
         if(Direction == DIR_BUY) {
            if(BuyB()) {
               Print("BUY B FOUND ON ", TimeToString(currentBar));

               if(!HasPosition()) {
                  if (adxBuy) {
                     EntryPrice = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
                     TradeSL = LastPivotLow(_Symbol, PERIOD_M15) - SLBuffer;
                     InitialRisk = EntryPrice - TradeSL;
                     TrendMode = IsH4BullTrend();
                     TradeTP = 0;

                     CurrentLot = CalcLot(
                        _Symbol,
                        ORDER_TYPE_BUY,
                        EntryPrice,
                        TradeSL,
                        RiskUSD,
                        MaxLot
                     );

                     bool result = trade.Buy(
                        CurrentLot,
                        _Symbol,
                        EntryPrice,
                        TradeSL,
                        TradeTP);

                     if(result) {
                        Print(
                           "BUY OPENED Lot=",
                           CurrentLot,
                           " SL=",
                           TradeSL,
                           " TP=",
                           TradeTP);

                        State = STATE_IN_TRADE;
                     }
                  } else {
                     State = STATE_WAIT_CROSS;
                  } // End of adxBuy
               } // End of !HasPosition
            } // End of BuyB()
            else {
               if (currentBar == A.Time + PeriodSeconds(PERIOD_M15)) {
                  if (BuyA()) {
                     ProcessBuyWaitA();
                  }
                  else{
                     State = STATE_WAIT_A;
                     Print("Not BuyB() -> BACK TO WAIT A");
                  }
               }
            }
         } // End of Direction == DIR_BUY

         if(Direction == DIR_SELL) {
            if(SellB()) {
               Print("SELL B FOUND ON ", TimeToString(currentBar));

               if(!HasPosition()) {
                  if (adxSell) {
                     EntryPrice = SymbolInfoDouble(_Symbol,SYMBOL_BID);
                     TradeSL = LastPivotHigh(_Symbol, PERIOD_M15) + SLBuffer;
                     InitialRisk = TradeSL - EntryPrice;
                     TrendMode = IsH4BearTrend();
                     TradeTP = 0;

                     CurrentLot = CalcLot(
                        _Symbol,
                        ORDER_TYPE_SELL,
                        EntryPrice,
                        TradeSL,
                        RiskUSD,
                        MaxLot
                     );

                     bool result = trade.Sell(
                        CurrentLot,
                        _Symbol,
                        EntryPrice,
                        TradeSL,
                        TradeTP);

                     if(result) {
                        Print(
                           "SELL OPENED Lot=",
                           CurrentLot,
                           " SL=",
                           TradeSL,
                           " TP=",
                           TradeTP);

                        State = STATE_IN_TRADE;
                     }
                  } else {
                     State = STATE_WAIT_CROSS;
                  } // End of adxSell
               } // End of !HasPosition()
            } // End of SellB()
            else {
               if (currentBar == A.Time + PeriodSeconds(PERIOD_M15)) {
                  if (SellA()) {
                     ProcessSellWaitA();
                  }
                  else {
                     State = STATE_WAIT_A;
                     Print("Not SellB() -> BACK TO WAIT A");
                  }
               }
            }
         } // End of Direction == DIR_SELL
      }
   }

   //--------------------------------------------------
   // DEBUG
   //--------------------------------------------------

   Print(
      "STATE = ",
      State,
      " | DIR = ",
      Direction
   );
}

//=====================================================
// ON INIT
//=====================================================

int OnInit()
{
   Print("EA STARTED");

   ADXHandle = iADX(
      _Symbol,
      PERIOD_H1,
      ADXPeriod);

   return(INIT_SUCCEEDED);
}

//=====================================================
// ON TICK
//=====================================================

void OnTick()
{
   ManageOpenPosition(
      trade,
      _Symbol,

      EntryPrice,
      InitialRisk,

      TrendMode,

      TrendTrailStartRR,
      TrendTrailStepRR,

      NonTrendTrailStartRR,
      NonTrendTrailStepRR,

      TradeSL,
      TradeTP
   );

   if (!IsNewBar(_Symbol, PERIOD_M15, LastM15Bar))
      return;

   ProcessStateMachine();
}
